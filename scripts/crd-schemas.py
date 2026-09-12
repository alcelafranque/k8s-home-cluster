#!/usr/bin/env python3
"""Extract kubeconform JSON schemas from the CRDs of the rendered operator chart."""
import copy
import json
from pathlib import Path
import sys

import yaml


def convert(schema):
    """Translate Kubernetes OpenAPI nullable/int-or-string to JSON Schema."""
    if not isinstance(schema, dict):
        return schema
    result = copy.deepcopy(schema)
    for key in ("properties", "definitions", "patternProperties"):
        if isinstance(result.get(key), dict):
            result[key] = {k: convert(v) for k, v in result[key].items()}
    for key in ("items", "additionalProperties", "not"):
        if isinstance(result.get(key), dict):
            result[key] = convert(result[key])
    for key in ("allOf", "anyOf", "oneOf"):
        if isinstance(result.get(key), list):
            result[key] = [convert(v) for v in result[key]]
    if result.pop("x-kubernetes-int-or-string", False):
        result.pop("type", None)
        result.setdefault("anyOf", [{"type": "integer"}, {"type": "string"}])
    if result.pop("nullable", False):
        return {"anyOf": [result, {"type": "null"}]}
    return result


def main():
    source, destination = map(Path, sys.argv[1:])
    count = 0
    for resource in yaml.safe_load_all(source.read_text()):
        if not resource or resource.get("kind") != "CustomResourceDefinition":
            continue
        spec = resource["spec"]
        for version in spec["versions"]:
            if not version.get("served"):
                continue
            schema = convert(version["schema"]["openAPIV3Schema"])
            target = destination / spec["group"] / (
                spec["names"]["kind"].lower() + "_" + version["name"] + ".json"
            )
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(schema))
            count += 1
    if count == 0:
        raise SystemExit("No served CRD schemas found in the operator render")
    print(f"Extracted {count} CRD schemas from the pinned operator chart")


if __name__ == "__main__":
    main()
