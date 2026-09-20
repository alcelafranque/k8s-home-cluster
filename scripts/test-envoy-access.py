#!/usr/bin/env python3
"""Exercise repository policies through egctl and a local Envoy (no cluster writes).

Requires PyYAML, egctl v1.9.1, Envoy v1.39.0 and a downloaded country MMDB.
Usage: python3 scripts/test-envoy-access.py EGCTL ENVOY COUNTRY_MMDB
"""

import ipaddress
import base64
import hashlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time

import yaml


ROOT = Path(__file__).resolve().parents[1]
APPS = ROOT / "kubernetes/apps"


def main():
    egctl, envoy, database = map(str, map(Path, sys.argv[1:]))
    documents = []
    paths = set(APPS.rglob("ingress.yaml")) | set((APPS / "envoy-gateway").rglob("*.yaml"))
    for path in sorted(paths):
        if "charts" in path.parts:
            continue
        for document in yaml.safe_load_all(path.read_text()):
            if isinstance(document, dict) and document.get("kind") in {
                "GatewayClass", "Gateway", "EnvoyProxy", "ClientTrafficPolicy",
                "SecurityPolicy", "HTTPRoute",
            }:
                metadata = document["metadata"]
                metadata["annotations"] = {k: str(v) for k, v in metadata.get("annotations", {}).items()}
                documents.append(document)
    # Test HTTPS application routes on plaintext loopback; TLS is unrelated to ACLs.
    secrets = []
    for doc in documents:
        if doc["kind"] == "Gateway":
            for listener in doc["spec"]["listeners"]:
                listener["protocol"] = "HTTP"
                listener.pop("tls", None)
        elif doc["kind"] == "EnvoyProxy":
            doc["spec"]["geoIP"]["provider"]["maxMind"]["countryDbSource"]["local"]["path"] = str(Path(database).resolve())
        elif doc["kind"] == "SecurityPolicy" and 'basicAuth' in doc['spec']:
            users = b'test:{SHA}' + base64.b64encode(hashlib.sha1(b'test').digest()) + b'\n'
            secrets.append({'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {
                'name': doc['spec']['basicAuth']['users']['name'], 'namespace': doc['metadata']['namespace']},
                'data': {'.htpasswd': base64.b64encode(users).decode()}})
    documents.extend(secrets)
    with tempfile.TemporaryDirectory(prefix="envoy-access-") as directory:
        tmp = Path(directory)
        inputs = tmp / "input.yaml"
        inputs.write_text(yaml.safe_dump_all(documents))
        translated = subprocess.run([
            egctl, "x", "translate", "--from", "gateway-api", "--to", "gateway-api,xds",
            "--type", "all", "--add-missing-resources", "-o", "json", "-f", str(inputs),
        ], capture_output=True, text=True)
        if translated.returncode:
            raise RuntimeError(translated.stderr + translated.stdout)
        (tmp / "translated.json").write_text(translated.stdout)
        bootstrap = json.loads(translated.stdout)
        for policy in bootstrap['securityPolicies'] + bootstrap['clientTrafficPolicies']:
            for ancestor in policy['status']['ancestors']:
                for condition in ancestor['conditions']:
                    if condition['type'] == 'Accepted':
                        assert condition['status'] == 'True', (policy['metadata'], condition)
        resources = bootstrap['xds']['envoy-gateway-system/one-gateway-for-all']
        dumps = {item['@type'].rsplit('.', 1)[-1]: item for item in resources['configs']}
        routes = {}
        for item in dumps['RoutesConfigDump']['dynamicRouteConfigs']:
            route = item['routeConfig']
            route.pop('@type', None)
            routes[route['name']] = route
            for host in route['virtualHosts']:
                for rule in host['routes']:
                    # Stub upstreams, preserving the actual translated security filters.
                    if 'route' in rule:
                        rule.pop('route')
                        rule['directResponse'] = {'status': 200}
        listeners, cases = [], []
        for item in dumps['ListenersConfigDump']['dynamicListeners']:
            listener = item['activeState']['listener']
            if not listener.get('name', '').startswith('envoy-gateway-system/'):
                continue
            listener.pop('@type', None)
            with socket.socket() as reserve:
                reserve.bind(('127.0.0.1', 0))
                port = reserve.getsockname()[1]
            listener['address'] = {'socketAddress': {'address': '127.0.0.1', 'portValue': port}}
            chains = listener.get('filterChains', []) + [listener.get('defaultFilterChain', {})]
            for chain in chains:
                for network_filter in chain.get('filters', []):
                    hcm = network_filter['typedConfig']
                    if 'rds' not in hcm:
                        continue
                    route = routes[hcm.pop('rds')['routeConfigName']]
                    hcm['routeConfig'] = route
                    hcm.pop('accessLog', None)
                    for host in route['virtualHosts']:
                        for domain in host['domains']:
                            if '*' not in domain:
                                cases.append((port, domain))
            listeners.append(listener)
        config = tmp / 'envoy.json'
        config.write_text(json.dumps({'staticResources': {'listeners': listeners}}))
        log = tmp / 'envoy.log'
        with log.open('w') as output:
            process = subprocess.Popen([envoy, '-c', str(config), '--concurrency', '1', '--log-level', 'error'], stdout=output, stderr=output)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError(log.read_text())
                    try:
                        with socket.create_connection(('127.0.0.1', cases[0][0]), timeout=.1):
                            break
                    except OSError:
                        time.sleep(.1)
                checks = 0
                for port, host in cases:
                    for ip in ['82.64.0.1', '8.8.8.8', '2001:67c:9ec::1', '2001:4860:4860::8888', '192.0.2.1']:
                        restricted_hosts = {'argocd.lac-coloc.fr', 'bichon.lafranque.net'}
                        allowed = (host == 'jellyfin.lac-coloc.fr' or
                                   (host in restricted_hosts and ip == '2001:67c:9ec::1') or
                                   (host not in restricted_hosts | {'jellyfin.lac-coloc.fr'} and ip in {'82.64.0.1', '2001:67c:9ec::1'}))
                        # A fake XFF and fake GeoIP country must never bypass a deny.
                        status = request(port, host, ip)
                        assert status in ({200, 301} if allowed else {403}), (host, ip, status, allowed)
                        checks += 1
                print(f'PASS: {checks} HTTP/HTTPS-route checks through PROXY v2; spoofed XFF/GeoIP headers included')
            finally:
                process.terminate()
                process.wait(timeout=10)


def request(port, host, ip):
    source = ipaddress.ip_address(ip)
    destination = ipaddress.ip_address('127.0.0.1' if source.version == 4 else '::1')
    addresses = source.packed + destination.packed + struct.pack('!HH', 54321, port)
    proxy = b'\r\n\r\n\x00\r\nQUIT\n' + bytes([0x21, 0x11 if source.version == 4 else 0x21]) + struct.pack('!H', len(addresses)) + addresses
    http = f'GET / HTTP/1.1\r\nHost: {host}\r\nAuthorization: Basic dGVzdDp0ZXN0\r\nX-Forwarded-For: 2001:67c:9ec::1\r\nx-eg-internal-geoip-country: FR\r\nConnection: close\r\n\r\n'.encode()
    with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
        client.sendall(proxy + http)
        response = client.recv(4096)
    return int(response.split(b' ')[1])


if __name__ == "__main__":
    main()
