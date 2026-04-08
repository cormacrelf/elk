"""
To run: `buck2 run :main`
"""

import numpy as np
import cowsay
import colorama
from colorama import Fore

colorama.init()
print(Fore.RED + cowsay.get_output_string("cow", str(np.arange(5))))
print(Fore.RESET)
