from colorama import Fore


def greet(name: str) -> str:
    return f"{Fore.GREEN}Hello, {name}!{Fore.RESET}"
