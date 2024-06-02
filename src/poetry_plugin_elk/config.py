from typing import Iterable, NamedTuple
from packaging.tags import MacVersion, PythonVersion

import tomllib


class PythonConfig(NamedTuple):
    python_version: PythonVersion
    interpreter: str
    cpython: bool


class LinuxConfig(NamedTuple):
    arch: str
    abis: Iterable[str]
    glibc_version: tuple[int, int]
    manylinux1_compatible: bool
    manylinux2010_compatible: bool
    manylinux2014_compatible: bool


class DarwinConfig(NamedTuple):
    macos_version: MacVersion
    arch: str
    abis: Iterable[str]


class Platform(NamedTuple):
    name: str
    python: PythonConfig
    platform: DarwinConfig | LinuxConfig


class BuckConfig(NamedTuple):
    file_name: str = "BUCK"
    buckfile_imports: str = ""
    # there's no good default for this yet
    alias: str = "alias"
    prebuilt_python_library: str = "prebuilt_python_library"
    python_library: str = "python_library"
    generated_file_header: str = ""


class ElkConfig(NamedTuple):
    python: PythonConfig
    platforms: list[Platform]
    buck: BuckConfig


def parse_toml(file) -> ElkConfig:
    data = tomllib.load(file)
    platforms = []

    buck = BuckConfig(**data.get("buck", {}))

    python = PythonConfig(
        python_version=tuple(data["python"]["version"]),
        interpreter=data["python"]["interpreter"],
        cpython=data["python"].get("cpython", True),
    )
    for name, config in data["platform"].items():
        platform_name = config.get("platform")
        if platform_name == "darwin":
            arch = "arm64" if config["arch"] == "aarch64" else config["arch"]
            platform = DarwinConfig(
                macos_version=tuple(list(config["macos_version"])[0:2]),
                arch=arch,
                abis=config["abi"],
            )
        elif platform_name == "linux":
            arch = "aarch64" if config["arch"] == "arm64" else config["arch"]
            platform = LinuxConfig(
                arch=arch,
                abis=config["abi"],
                glibc_version=tuple(list(config["glibc_version"])[0:2]),
                manylinux1_compatible=config.get("manylib1_compatible", False),
                manylinux2010_compatible=config.get("manylib2010_compatible", False),
                manylinux2014_compatible=config.get("manylib2014_compatible", False),
            )
        else:
            raise ValueError(f"Unsupported platform: {platform_name}")

        platforms.append(Platform(name=name, python=python, platform=platform))

    return ElkConfig(python=python, platforms=platforms, buck=buck)
