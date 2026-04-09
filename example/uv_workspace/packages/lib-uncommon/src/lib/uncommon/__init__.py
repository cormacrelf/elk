from colorama import Fore


def farewell(name: str) -> str:
    return f"{Fore.YELLOW}Goodbye, {name}!{Fore.RESET}"
