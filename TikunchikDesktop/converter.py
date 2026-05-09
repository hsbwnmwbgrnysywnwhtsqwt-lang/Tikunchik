MAPPING = {
    'q': '/', 'w': "'", 'e': 'ק', 'r': 'ר', 't': 'א',
    'y': 'ט', 'u': 'ו', 'i': 'ן', 'o': 'ם', 'p': 'פ',
    '[': ']', ']': '[',
    'a': 'ש', 's': 'ד', 'd': 'ג', 'f': 'כ', 'g': 'ע',
    'h': 'י', 'j': 'ח', 'k': 'ל', 'l': 'ך', ';': 'ף',
    "'": ',',
    'z': 'ז', 'x': 'ס', 'c': 'ב', 'v': 'ה', 'b': 'נ',
    'n': 'מ', 'm': 'צ', ',': 'ת', '.': 'ץ', '/': '.',
}

REVERSE_MAPPING = {v: k for k, v in MAPPING.items()}


class SpellChecker:
    def __init__(self):
        self._en = None
        self._he = None
        try:
            import enchant
            for lang in ("en_US", "en"):
                if enchant.dict_exists(lang):
                    self._en = enchant.Dict(lang)
                    break
            for lang in ("he", "he_IL"):
                if enchant.dict_exists(lang):
                    self._he = enchant.Dict(lang)
                    break
        except ImportError:
            pass

    @property
    def available(self):
        return self._en is not None or self._he is not None

    def is_english_word(self, word):
        stripped = word.strip('.,;:!?"\'-')
        if len(stripped) < 2 or not self._en:
            return False
        return self._en.check(stripped)

    def is_hebrew_word(self, word):
        stripped = word.strip('.,;:!?"\'-')
        if len(stripped) < 2 or not self._he:
            return False
        return self._he.check(stripped)


def _is_hebrew_char(ch):
    code = ord(ch)
    return (0x0590 <= code <= 0x05FF) or (0xFB1D <= code <= 0xFB4F)


def _is_latin_char(ch):
    code = ord(ch)
    return (0x0041 <= code <= 0x005A) or (0x0061 <= code <= 0x007A)


def _dominant_script(token):
    latin = sum(1 for c in token if _is_latin_char(c))
    hebrew = sum(1 for c in token if _is_hebrew_char(c))
    if latin == 0 and hebrew == 0:
        return "unknown"
    return "hebrew" if hebrew > latin else "latin"


def _map_characters(token, table):
    result = []
    for ch in token:
        lower = ch.lower()
        mapped = table.get(lower, ch)
        if ch.isupper():
            mapped = mapped.upper()
        result.append(mapped)
    return "".join(result)


def convert_text(text, checker=None):
    parts = []
    word = []
    for ch in text:
        if ch in (" ", "\t", "\n", "\r"):
            if word:
                parts.append(("".join(word), True))
                word = []
            parts.append((ch, False))
        else:
            word.append(ch)
    if word:
        parts.append(("".join(word), True))

    word_parts = [p for p in parts if p[1]]
    clear_convert_count = 0

    for token, _ in word_parts:
        script = _dominant_script(token)
        if script == "latin":
            hebrew = _map_characters(token, MAPPING)
            if checker and checker.available:
                if checker.is_hebrew_word(hebrew) or not checker.is_english_word(token):
                    clear_convert_count += 1
            else:
                clear_convert_count += 1
        elif script == "hebrew":
            if checker and checker.available and not checker.is_hebrew_word(token):
                clear_convert_count += 1

    majority_converting = clear_convert_count > len(word_parts) // 2

    result = []
    for token, is_word in parts:
        if not is_word:
            result.append(token)
            continue

        script = _dominant_script(token)
        if script == "latin":
            hebrew = _map_characters(token, MAPPING)
            if checker and checker.available:
                if checker.is_hebrew_word(hebrew) or not checker.is_english_word(token) or majority_converting:
                    result.append(hebrew)
                else:
                    result.append(token)
            else:
                result.append(hebrew)
        elif script == "hebrew":
            if checker and checker.available and checker.is_hebrew_word(token):
                result.append(token)
            else:
                result.append(_map_characters(token, REVERSE_MAPPING))
        else:
            result.append(token)

    return "".join(result)
