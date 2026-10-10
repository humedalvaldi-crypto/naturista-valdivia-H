"""Censura línea a línea (stdin → stdout) y guarda una copia censurada en el archivo indicado."""
import re
import sys

RULES = [
    (re.compile(r"-----BEGIN[^-]*-----.*?-----END[^-]*-----", re.S), "<clave>"),
    (re.compile(r"X'[0-9a-fA-F]*'"), "X'…'"),
    (re.compile(r"'(?:[^']|'')*'"), "'…'"),
    (re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+"), "<correo>"),
    (re.compile(r"user-files/\S+"), "user-files/<ruta>"),
    (re.compile(r"\b[A-Za-z0-9]{28}\b"), "<uid>"),
]


def redact(text: str) -> str:
    for pattern, repl in RULES:
        text = pattern.sub(repl, text)
    return text


with open(sys.argv[1], "w", encoding="utf-8") as copy:
    for line in sys.stdin:
        safe = redact(line)
        sys.stdout.write(safe)
        copy.write(safe)
