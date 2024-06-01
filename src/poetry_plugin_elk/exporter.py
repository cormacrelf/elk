from pathlib import Path
from typing import Collection, Iterable, Optional
from cleo.io.io import IO
from packaging.utils import NormalizedName
from poetry.core.packages.dependency_group import MAIN_GROUP
from poetry.installation.executor import Chooser, Executor
from poetry.poetry import Poetry

from poetry_plugin_export.walker import get_project_dependency_packages

from poetry_plugin_elk import buck
from poetry_plugin_elk.config import ElkConfig
from poetry_plugin_elk.envs import to_env


class Exporter:
    poetry: Poetry
    io: IO
    _output: Optional[Path]

    def __init__(
        self, poetry: Poetry, io: IO, executor: Executor, config: ElkConfig
    ) -> None:
        self._poetry = poetry
        self._io = io
        self._output = None
        self._extras: Collection[NormalizedName] = ()
        self._groups: Iterable[str] = [MAIN_GROUP]
        self._executor: Executor = executor
        self._config: ElkConfig = config

    def with_extras(self, extras: Collection[NormalizedName]) -> "Exporter":
        self._extras = extras
        return self

    def run(self) -> int:
        from poetry.core.packages.utils.utils import path_to_url

        with_extras = True
        allow_editable = False

        BUCK = buck.BUCK()

        root = self._poetry.package.with_dependency_groups(
            list(self._groups), only=True
        )
        for dependency_package in get_project_dependency_packages(
            self._poetry.locker,
            project_requires=root.all_requires,
            root_package_name=root.name,
            project_python_marker=root.python_marker,
            extras=self._extras,
        ):
            line = ""
            self._io.write_error_line(str(dependency_package.dependency))

            if not with_extras:
                dependency_package = dependency_package.without_features()

            dependency = dependency_package.dependency
            package = dependency_package.package

            if package.develop and not allow_editable:
                self._io.write_error_line(
                    f"<warning>Warning: {package.pretty_name} is locked in develop"
                    " (editable) mode, which is incompatible with the"
                    " constraints.txt format.</warning>"
                )
                continue

            requirement = dependency.to_pep_508(with_extras=False, resolved=True)
            is_direct_local_reference = (
                dependency.is_file() or dependency.is_directory()
            )
            is_direct_remote_reference = dependency.is_vcs() or dependency.is_url()

            deps = [buck.TargetName(dep.name) for dep in package.all_requires]

            alias: buck.Alias
            platform_actual = {}
            for plat in self._config.platforms:
                env = to_env(plat)
                c = self._executor._chooser
                chooser = Chooser(c._pool, env, c._config)
                link = chooser.choose_for(package)
                target: buck.SourceArchive | buck.WheelDownload
                built: buck.Target
                if link.filename.endswith(".whl"):
                    target = buck.WheelDownload(package=package, link=link)
                    BUCK.push(target)
                    built = buck.WheelBuild(
                        rule=self._config.buck.prebuilt_python_library,
                        package=package,
                        binary_src=target.target_name(),
                        deps=deps,
                    )
                    BUCK.push(built)
                else:
                    target = buck.SourceArchive(package=package, link=link)
                    BUCK.push(target)
                    built = buck.SourceBuild(
                        package=package, source=target.target_name(), deps=deps
                    )
                    BUCK.push(built)
                    # self._io.write_error_line(
                    #     f"<warning>Could not choose a wheel for package {package}, for config {conf}</warning>"
                    # )
                    # for link in chooser._get_links(package):
                    #     self._io.write_error_line(
                    #         "<error>    " + link.filename + "</error>"
                    #     )
                    # return 1
                platform_actual[plat.name] = built.target_name()

            alias = buck.Alias(
                rule=self._config.buck.alias, name=package.name, actual=platform_actual
            )
            BUCK.push(alias)

            if is_direct_remote_reference:
                line = requirement
            elif is_direct_local_reference:
                assert dependency.source_url is not None
                dependency_uri = path_to_url(dependency.source_url)
                if package.develop:
                    line = f"-e {dependency_uri}"
                else:
                    line = f"{package.complete_name} @ {dependency_uri}"
            else:
                line = f"{package.complete_name}=={package.version}"

            if not is_direct_remote_reference and ";" in requirement:
                markers = requirement.split(";", 1)[1].strip()
                if markers:
                    line += f" ; {markers}"

            if (
                not is_direct_remote_reference
                and not is_direct_local_reference
                and package.source_url
            ):
                self._io.write_line(package.source_url.rstrip("/"))

        # only open the file (& truncate it) when we get this far
        with open(self._config.buck.file_name, "w+") as output:
            output.write(self._config.buck.generated_file_header)
            output.write("\n")
            output.write(self._config.buck.buckfile_imports)
            output.write("\n")
            BUCK.dump(output)

        return 0
