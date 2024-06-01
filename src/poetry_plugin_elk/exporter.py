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

    def run(self, output_path: Path) -> int:
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
            if not with_extras:
                dependency_package = dependency_package.without_features()

            package = dependency_package.package

            if package.develop and not allow_editable:
                self._io.write_error_line(
                    f"<warning>Warning: {package.pretty_name} is locked in develop"
                    " (editable) mode, which is incompatible with the"
                    " constraints.txt format.</warning>"
                )
                continue

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
                    # target = buck.SourceArchive(package=package, link=link)
                    # BUCK.push(target)
                    # built = buck.SourceBuild(
                    #     package=package, source=target.target_name(), deps=deps
                    # )
                    # BUCK.push(built)
                    self._io.write_error_line(
                        f"<error>Could not choose a wheel for package {package}, for config {plat}</error>"
                    )
                    self._io.write_error_line(f"<error>Available wheels:</error>")
                    for link in chooser._get_links(package):
                        self._io.write_error_line(
                            "<error>    " + link.filename + "</error>"
                        )
                    return 1
                platform_actual[plat.name] = built.target_name()

            alias = buck.Alias(
                rule=self._config.buck.alias, name=package.name, actual=platform_actual
            )
            BUCK.push(alias)

        # only open the file (& truncate it) when we get this far
        with open(output_path, "w+") as output:
            output.write(self._config.buck.generated_file_header)
            output.write("\n")
            output.write(self._config.buck.buckfile_imports)
            output.write("\n")
            BUCK.dump(output)

        return 0
