import cowsay
from lib.common import greet
from lib.uncommon import farewell


def run():
    print(greet("cli"))
    print(farewell("cli"))
    cowsay.cow("moo from cli")
