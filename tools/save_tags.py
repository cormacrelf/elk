"""Write platform packaging tags as JSON.

Usage:
    buck2 run elk//tools:save_tags -- linux-x86_64.tags.json
    buck2 run elk//tools:save_tags -- -  # stdout

Requires the `packaging` package to be installed in the interpreter.
"""

import json
import sys

from packaging.tags import sys_tags


def main():
    if len(sys.argv) != 2:
        print("Usage: save_tags <filename>", file=sys.stderr)
        print("  Use - for stdout", file=sys.stderr)
        sys.exit(1)

    dest = sys.argv[1]
    tags = [str(t) for t in sys_tags()]

    if dest == "-":
        json.dump(tags, sys.stdout, indent=4)
        print()
    else:
        with open(dest, "w+") as f:
            json.dump(tags, f, indent=4)
            _ = f.write("\n")
        print("Saved {} tags to {}".format(len(tags), dest), file=sys.stderr)


if __name__ == "__main__":
    main()
