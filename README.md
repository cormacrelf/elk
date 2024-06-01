# Elk

Like [`reindeer`](https://github.com/facebookincubator/reindeer) but for
Python + [Poetry](https://python-poetry.org) dependencies.


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


### Using the poetry virtualenv for e.g. code completion

Poetry still works, and you can just hook into that.
Configure `pyright` as usual, then:

    cd example
    poetry -C pypi run nvim

Or otherwise use poetry to enter a shell with the virtualenv in it.

If you have a lot of python packages, and you've used `elk`
to place all their dependencies in a single BUCK file, then you will
get too many packages available in your language server, but Buck will
still precisely set up the paths when you `buck2 run`.

If you want your editor to exactly reflect the dependencies added,
then I'm sure we can make Buck build a virtualenv using a BXL script.
