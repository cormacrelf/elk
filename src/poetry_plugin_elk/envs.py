from typing import Iterable, Iterator, NamedTuple
from packaging.tags import (
    MacVersion,
    PythonVersion,
    Tag,
    compatible_tags,
    cpython_tags,
    generic_tags,
    mac_platforms,
)
from poetry.utils.env import MockEnv


class FixedConfig(NamedTuple):
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
    mac_version: MacVersion
    arch: str
    abis: Iterable[str]


def tags(
    f: FixedConfig, abis: Iterable[str], platforms: Iterable[str]
) -> Iterator[Tag]:
    if f.cpython:
        yield from cpython_tags(
            python_version=f.python_version,
            abis=abis,
            platforms=platforms,
        )
    else:
        yield from generic_tags(
            interpreter=f.interpreter,
            abis=abis,
            platforms=platforms,
        )
    yield from compatible_tags(
        python_version=f.python_version,
        interpreter=f.interpreter,
        platforms=platforms,
    )


def macos_tags(f: FixedConfig, darwin: DarwinConfig) -> Iterator[Tag]:
    arch = "arm64" if darwin.arch == "aarch64" else darwin.arch
    return tags(f, darwin.abis, mac_platforms(version=darwin.mac_version, arch=arch))


def manylinux(archs: Iterable[str], linux: LinuxConfig) -> Iterator[str]:
    from packaging.tags import _manylinux

    # From PEP 513, PEP 600
    def _is_compatible(arch: str, version: _manylinux._GLibCVersion) -> bool:
        # sys_glibc = _get_glibc_version()
        # if sys_glibc < version:
        #     return False
        # Check for presence of _manylinux module.
        # try:
        #     import _manylinux
        # except ImportError:
        #     return True
        # if hasattr(_manylinux, "manylinux_compatible"):
        #     result = _manylinux.manylinux_compatible(version[0], version[1], arch)
        #     if result is not None:
        #         return bool(result)
        #     return True
        if version == _manylinux._GLibCVersion(2, 5):
            return bool(linux.manylinux1_compatible)
        if version == _manylinux._GLibCVersion(2, 12):
            return bool(linux.manylinux2010_compatible)
        if version == _manylinux._GLibCVersion(2, 17):
            return bool(linux.manylinux2014_compatible)
        return True

    # Oldest glibc to be supported regardless of architecture is (2, 17).
    too_old_glibc2 = _manylinux._GLibCVersion(2, 16)
    if set(archs) & {"x86_64", "i686"}:
        # On x86/i686 also oldest glibc to be supported is (2, 5).
        too_old_glibc2 = _manylinux._GLibCVersion(2, 4)
    current_glibc = _manylinux._GLibCVersion(*linux.glibc_version)
    glibc_max_list = [current_glibc]
    # We can assume compatibility across glibc major versions.
    # https://sourceware.org/bugzilla/show_bug.cgi?id=24636
    #
    # Build a list of maximum glibc versions so that we can
    # output the canonical list of all glibc from current_glibc
    # down to too_old_glibc2, including all intermediary versions.
    for glibc_major in range(current_glibc.major - 1, 1, -1):
        glibc_minor = _manylinux._LAST_GLIBC_MINOR[glibc_major]
        glibc_max_list.append(_manylinux._GLibCVersion(glibc_major, glibc_minor))
    for arch in archs:
        for glibc_max in glibc_max_list:
            if glibc_max.major == too_old_glibc2.major:
                min_minor = too_old_glibc2.minor
            else:
                # For other glibc major versions oldest supported is (x, 0).
                min_minor = -1
            for glibc_minor in range(glibc_max.minor, min_minor, -1):
                glibc_version = _manylinux._GLibCVersion(glibc_max.major, glibc_minor)
                tag = "manylinux_{}_{}".format(*glibc_version)
                if _is_compatible(arch, glibc_version):
                    yield f"{tag}_{arch}"
                # Handle the legacy manylinux1, manylinux2010, manylinux2014 tags.
                if glibc_version in _manylinux._LEGACY_MANYLINUX_MAP:
                    legacy_tag = _manylinux._LEGACY_MANYLINUX_MAP[glibc_version]
                    if _is_compatible(arch, glibc_version):
                        yield f"{legacy_tag}_{arch}"


def linux_platforms(linux: LinuxConfig) -> Iterator[str]:
    archs = {"armv8l": ["armv8l", "armv7l"]}.get(linux.arch, [linux.arch])
    yield from manylinux(archs, linux)
    # from packaging.tags import _musllinux
    # yield from _musllinux.platform_tags(archs)
    for arch in archs:
        yield f"linux_{arch}"


def linux_tags(
    f: FixedConfig,
    linux: LinuxConfig,
) -> Iterator[Tag]:
    platforms = linux_platforms(linux)
    return tags(f, linux.abis, platforms)


class Config(NamedTuple):
    name: str
    fixed: FixedConfig
    platform: DarwinConfig | LinuxConfig

    def to_env(self) -> MockEnv:
        if type(self.platform) is DarwinConfig:
            return MockEnv(
                platform="darwin",
                platform_machine=self.platform.arch,
                supported_tags=list(macos_tags(self.fixed, self.platform)),
            )
        elif type(self.platform) is LinuxConfig:
            return MockEnv(
                platform="linux",
                platform_machine=self.platform.arch,
                supported_tags=list(linux_tags(self.fixed, self.platform)),
            )
        else:
            raise Exception("self.platform was neither LinuxConfig nor DarwinConfig")


_fixed = FixedConfig(
    python_version=(3, 12),
    interpreter="cp312",
    cpython=True,
)
_abis = ("cp312", "abi3", "none")
_linux = {
    "manylinux1_compatible": False,
    "manylinux2010_compatible": True,
    "manylinux2014_compatible": True,
}

EXAMPLE_CONFIGS = [
    Config(
        name="macos-arm64",
        fixed=_fixed,
        platform=DarwinConfig(
            mac_version=(13, 0),
            arch="arm64",
            abis=_abis,
        ),
    ),
    Config(
        name="macos-x86_64",
        fixed=_fixed,
        platform=DarwinConfig(
            mac_version=(13, 0),
            arch="x86_64",
            abis=_abis,
        ),
    ),
    Config(
        name="linux-arm64",
        fixed=_fixed,
        platform=LinuxConfig(
            arch="aarch64", abis=_abis, glibc_version=(2, 38), **_linux
        ),
    ),
    Config(
        name="linux-aarch64",
        fixed=_fixed,
        platform=LinuxConfig(
            arch="x86_64", abis=_abis, glibc_version=(2, 38), **_linux
        ),
    ),
]
