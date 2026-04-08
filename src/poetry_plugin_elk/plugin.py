from pathlib import Path
from typing import Iterable
from cleo.helpers import argument, option
from poetry.plugins.application_plugin import ApplicationPlugin
from poetry.console.application import Application
from poetry.console.commands.installer_command import InstallerCommand
from poetry.console.commands.command import Command

from packaging.utils import NormalizedName, canonicalize_name

from poetry_plugin_elk.exporter import Exporter
from poetry_plugin_elk.config import parse_toml


class CustomCommand(InstallerCommand):
    name = "elk"

    options = [
        option(
            "extras",
            "E",
            "Extra sets of dependencies to include.",
            flag=False,
            multiple=True,
        ),
        option("all-extras", None, "Include all sets of extra dependencies."),
    ]

    def handle(self) -> int:
        # self.installer.lock(update=False)
        # self.installer.dry_run(dry_run=True)
        config_path = self.poetry.pyproject_path.parent / Path("elk.toml")
        config = parse_toml(config_path)
        output_path = self.poetry.pyproject_path.parent / Path(config.buck.file_name)

        locker = self.poetry.locker
        if not locker.is_locked():
            self.line_error("<comment>The lock file does not exist. Locking.</comment>")
            options = []
            if self.io.is_debug():
                options.append(("-vvv", None))
            elif self.io.is_very_verbose():
                options.append(("-vv", None))
            elif self.io.is_verbose():
                options.append(("-v", None))

            self.call("lock", " ".join(options))  # type: ignore[arg-type]

        extras: Iterable[NormalizedName]
        if self.option("all-extras"):
            extras = self.poetry.package.extras.keys()
        else:
            extras = {
                canonicalize_name(extra)
                for extra_opt in self.option("extras")
                for extra in extra_opt.split()
            }
            invalid_extras = extras - self.poetry.package.extras.keys()
            if invalid_extras:
                raise ValueError(
                    f"Extra [{', '.join(sorted(invalid_extras))}] is not specified."
                )
        exporter = Exporter(self.poetry, self.io, self.installer.executor, config)
        return exporter.with_extras(extras).run(output_path)


class SaveTagsCommand(Command):
    name = "elk-save-tags"
    description = (
        "Save packaging tags for the current system to a {name}.tags.json file"
    )

    arguments = [
        argument(
            "name", "Platform name matching a [platform.NAME] section in elk.toml"
        ),
    ]

    def handle(self) -> int:
        import json
        import platform as platform_mod
        from packaging.tags import sys_tags

        plat_name = self.argument("name")
        output_path = Path(f"{plat_name}.tags.json")
        tag_list = [str(t) for t in sys_tags()]

        with open(output_path, "w") as f:
            json.dump(tag_list, f, indent=4)
            f.write("\n")

        self.line(f"<info>Saved {len(tag_list)} tags to {output_path}</info>")
        return 0


class Elk(ApplicationPlugin):
    @property
    def commands(self) -> list[type[Command]]:
        return [CustomCommand, SaveTagsCommand]

    def activate(self, application: Application):
        super().activate(application=application)
