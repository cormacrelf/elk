from io import TextIOWrapper
import json
from typing import Any, NamedTuple, Optional

from cleo.io.io import IO
from poetry.core.packages.package import Package
from poetry.installation.executor import Link


def tobuck(i: int, x: Any) -> str:
    def ltobuck(i: int, x: list[Any]) -> str:
        s = "["
        indent0 = "\n" + (" " * (4 * i))
        indent1 = "\n" + (" " * (4 * (i + 1)))
        for y in x:
            s += indent1
            s += tobuck(i + 1, y)
            s += ","
        s += indent0 + "]" if x else "]"
        return s

    def dtobuck(i: int, x: dict[Any, Any]) -> str:
        s = "{"
        indent0 = "\n" + (" " * (4 * i))
        indent1 = "\n" + (" " * (4 * (i + 1)))
        for k, v in x.items():
            s += indent1
            s += json.dumps(k)
            s += ": "
            s += tobuck(i + 1, v)
            s += ","
        s += indent0 + "}" if x else "}"
        return s

    if hasattr(x, "toJSON"):
        return x.toJSON(i)
    elif type(x) is list:
        return ltobuck(i, x)
    elif type(x) is dict:
        return dtobuck(i, x)

    return json.dumps(x, indent=4).replace("\n", "\n    ").replace('"\n', '",\n')


class TargetName(NamedTuple):
    name: str

    def __str__(self) -> str:
        return f":{self.name}"

    def toJSON(self, _: int):
        return f'":{self.name}"'


class Target:
    rule: str
    name: str
    metadata: Optional[dict[str, str]]
    labels: Optional[list[str]]
    visibility: Optional[list[str]]

    def __init__(self, rule: str, _fields: list[str], **kwargs):
        self.rule = rule
        self._fields = ["name"] + _fields + ["metadata", "labels", "visibility"]
        for k, v in kwargs.items():
            setattr(self, k, v)

    def _asdict(self) -> dict[str, Any]:
        return {k: getattr(self, k) for k in self._fields if hasattr(self, k)}

    def __str__(self) -> str:
        s = f"{self.rule}(\n"
        for k, v in self._asdict().items():
            v = tobuck(1, v)
            s += f"    {k} = {v},\n"
        s += ")"
        return s

    def target_name(self) -> TargetName:
        return TargetName(name=self.name)


class RemoteFile(Target):
    url: str
    sha256: str

    def __init__(self, **kwargs):
        super().__init__("remote_file", ["url", "sha256"], **kwargs)


class HttpArchive(Target):
    urls: list[str]
    sha256: str
    strip_prefix: Optional[str]

    def __init__(self, **kwargs):
        super().__init__("http_archive", ["urls", "sha256", "strip_prefix"], **kwargs)


class SourceArchive(HttpArchive):
    package: Package
    link: Link

    def __init__(self, package: Package, link: Link):
        name = link.filename
        self.package = package
        self.link = link
        super().__init__(
            name=name, urls=[link.url_without_fragment], sha256=link.hashes["sha256"]
        )


class WheelDownload(RemoteFile):
    package: Package
    link: Link

    def __init__(
        self,
        package: Package,
        link: Link,
    ) -> None:
        name = link.filename
        self.package = package
        self.link = link
        # name = self.package.unique_name + "-download"
        # wheel filenames should be unique enough
        super().__init__(
            name=name, url=link.url_without_fragment, sha256=link.hashes["sha256"]
        )


# much like prebuilt_python_library, which only takes name / binary_src / deps
#
#     prebuilt_python_library(
#       name = "requests",
#       binary_src = ":requests-blah.whl",
#     )
#
# But relies on a wrapper script to resolve the binary_src
class WheelBuild(Target):
    package: Package
    binary_src: TargetName
    deps: list[TargetName]

    def __init__(
        self,
        rule: str,
        package: Package,
        binary_src: TargetName,
        deps: list[TargetName],
        **kwargs,
    ):
        self.name = binary_src.name + "-built"
        self.package = package
        self.binary_src = binary_src
        self.deps = deps
        super().__init__(
            rule,
            ["binary_src", "deps", "exclude_deps_from_merged_linking"],
            **kwargs,
        )


class SourceBuild(Target):
    package: Package
    deps: list[TargetName]

    def __init__(
        self, package: Package, source: TargetName, deps: list[TargetName], **kwargs
    ):
        self.name = source.name + "-built"
        self.srcs = [source]
        self.package = package
        self.deps = deps
        super().__init__(
            "python_library",
            ["srcs", "deps", "exclude_deps_from_merged_linking"],
            **kwargs,
        )


class Alias(Target):
    """
    An alias rule, but with platform-dependent selection

        python.alias(
            name = "numpy",
            platform = {
                "linux-x86_64": ":some-wheel.whl",
                "macos-arm64": ":some-other-wheel.whl",
            },
        )

    """

    actual: TargetName | dict[str, TargetName]

    def __init__(self, rule: str, name: str, actual: dict[str, TargetName], **kwargs):
        self.name = name
        self.visibility = ["PUBLIC"]
        if len(actual) > 0:
            first = next(iter(actual.values()))
            if all(map(lambda v: v.name == first.name, actual.values())):
                self.actual = first
            else:
                self.actual = actual

        super().__init__(rule, ["actual"], **kwargs)


def coalesce():
    pass


# class PlatformFixups(NamedTuple):
#     platforms: dict[str, dict[str, Any]]
#     pass


class BUCK:
    targets: dict[TargetName, Target]

    def __init__(self) -> None:
        self.targets = {}

    def push(self, target: Target, replace=False):
        name = target.target_name()
        if name in self.targets and not replace:
            return
        # raise Exception(f"duplicate target name {name}")
        self.targets[name] = target

    def dump(self, file: TextIOWrapper | IO):
        for target in self.targets.values():
            file.write(str(target))
            file.write("\n")
            file.write("\n")
