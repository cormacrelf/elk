import numpy as np
from lib.common import greet


def run():
    print(greet("server"))
    print(f"numpy version: {np.__version__}")
