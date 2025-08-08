#!/usr/bin/env python3

# This script "Cofide-ifies" the SPIRE Helm charts, removing unsupported content.
# This should be applied in a CI pipeline, prior to releasing the charts.
# The resulting changes should not be committed to the repository to avoid a
# significant divergence from upstream SPIRE and resulting maintenance burden.

import contextlib
import pathlib
from ruamel.yaml import YAML
import shutil

yaml = YAML()
yaml.indent(sequence=4, offset=2)
yaml.line_width = 4096
yaml.preserve_quotes = True

CHARTS_TO_RM = ["spire-nested"]
SUBCHARTS_TO_RM = {
    "spire": [
        "spike-keeper",
        "spike-nexus",
        "spike-pilot",
        "tornjak-frontend",
    ],
}
ALIASES_TO_RM = {
    "spire": [
        "upstream-spiffe-csi-driver",
        "upstream-spire-agent",
    ]
}


# filter_chart_deps applies filter_func to a chart's dependencies in
# Chart.yaml, removing any for which the function returns false.
def filter_chart_deps(chart_name, filter_func):
    chart_yaml_path = pathlib.Path("charts", chart_name, "Chart.yaml")
    with open(chart_yaml_path, "r") as f:
        chart_yaml = yaml.load(f)

    filtered_deps = []
    for dep in chart_yaml["dependencies"]:
        if filter_func(dep):
            filtered_deps.append(dep)
        else:
            print(f"Removing {dep['name']} (alias {dep.get('alias')}) from chart {chart_name} dependencies")

    chart_yaml["dependencies"] = filtered_deps

    with open(chart_yaml_path, "w") as f:
        yaml.dump(chart_yaml, f)


def main():
    for chart in CHARTS_TO_RM:
        print(f"Removing unsupported chart {chart}")
        shutil.rmtree(pathlib.Path("charts", chart))

    for chart, subcharts in SUBCHARTS_TO_RM.items():
        for subchart in subcharts:
            print(f"Removing unsupported subchart {subchart} in {chart}")
            shutil.rmtree(pathlib.Path("charts", chart, "charts", subchart))

        filter_chart_deps(chart, lambda dep: dep["name"] not in subcharts)

    for chart, aliases in ALIASES_TO_RM.items():
        filter_chart_deps(chart, lambda dep: dep.get("alias") not in aliases)


if __name__ == "__main__":
    main()
