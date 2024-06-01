# Elk

Generate [Buck](https://buck2.build) build files from Python + 
[Poetry](https://python-poetry.org) dependencies.

Much like [`reindeer`](https://github.com/facebookincubator/reindeer).


### Status: experimental

Not seriously tested on a big python codebase. But it does do toy examples.
It will probably break if there is more than one version of a particular 
dependency.

### Install

```sh
pipx install poetry
pipx inject poetry .
```

### Quick start

Just follow along with the `example` folder. You'll probably want to copy the 
`elk.toml` and `platform.bzl` files.

### Use buck2 to assemble the virtualenv for e.g. code completion

See `example/venv.sh`.

Configure `pyright` as usual, then:

```sh
cd example
./venv.sh :main nvim main.py
```

Your editor will reflect the dependencies added in example/BUCK.
So if you edit the other target, you won't get access to the packages
`cowsay` and `colorama`:

```sh
./venv.sh :other nvim other.py
```

### Using the poetry virtualenv for e.g. code completion

Poetry still works, and you can just hook into that.
Configure `pyright` as usual, then:

    cd example
    poetry -C pypi run nvim

Or otherwise use poetry to enter a shell with the virtualenv in it.

If you have a lot of python packages, and you've used `elk`
to place all their dependencies in a single BUCK file, then you will
get too many packages available in your language server, but Buck will
still precisely set up the paths when you `buck2 run`. Overall this might
be less annoying than getting the virtualenv path from buck.

