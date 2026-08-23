/// Lightweight ODK-XPath-lite expression evaluator for the generic
/// BIODIVERSITE/SOCIAL survey engine.
///
/// Supports the exact subset of expressions found across the 11 uploaded
/// XLSForm files:
///  - relevant:   ${field}='value' | ${field}!='value' | selected(${f},'v')
///                | not(selected(${f},'v')) | (...) combined with or/and
///  - choiceFilter: "filter=${field}" or "type=${field}" (same semantics:
///                match against ChoiceItem.type using the referenced field's
///                current value)
///  - calculation: concat(...), format-date(${f},'%d%m%y'),
///                format-date-time(${f},'%H%M%S')
///  - constraint: ".>0", ". >= 0" (self-reference numeric constraints)
library;

enum _TokType {
  lparen,
  rparen,
  comma,
  or,
  and,
  not,
  selected,
  field,
  string,
  number,
  op,
  dot,
  ident,
}

class _Token {
  final _TokType type;
  final String text;
  _Token(this.type, this.text);
}

final RegExp _tokenPattern = RegExp(
  r"\$\{([a-zA-Z0-9_]+)\}"
  r"|'([^']*)'"
  r'|"([^"]*)"'
  r"|(!=|>=|<=|=|>|<)"
  r"|(\()"
  r"|(\))"
  r"|(,)"
  r"|(\bor\b)"
  r"|(\band\b)"
  r"|(\bnot\b)"
  r"|(\bselected\b)"
  r"|(-?\d+\.?\d*)"
  r"|(\.)"
  r"|([a-zA-Z_][a-zA-Z0-9_-]*)",
);

List<_Token> _tokenize(String expr) {
  final tokens = <_Token>[];
  for (final m in _tokenPattern.allMatches(expr)) {
    if (m.group(1) != null) {
      tokens.add(_Token(_TokType.field, m.group(1)!));
    } else if (m.group(2) != null) {
      tokens.add(_Token(_TokType.string, m.group(2)!));
    } else if (m.group(3) != null) {
      tokens.add(_Token(_TokType.string, m.group(3)!));
    } else if (m.group(4) != null) {
      tokens.add(_Token(_TokType.op, m.group(4)!));
    } else if (m.group(5) != null) {
      tokens.add(_Token(_TokType.lparen, '('));
    } else if (m.group(6) != null) {
      tokens.add(_Token(_TokType.rparen, ')'));
    } else if (m.group(7) != null) {
      tokens.add(_Token(_TokType.comma, ','));
    } else if (m.group(8) != null) {
      tokens.add(_Token(_TokType.or, 'or'));
    } else if (m.group(9) != null) {
      tokens.add(_Token(_TokType.and, 'and'));
    } else if (m.group(10) != null) {
      tokens.add(_Token(_TokType.not, 'not'));
    } else if (m.group(11) != null) {
      tokens.add(_Token(_TokType.selected, 'selected'));
    } else if (m.group(12) != null) {
      tokens.add(_Token(_TokType.number, m.group(12)!));
    } else if (m.group(13) != null) {
      tokens.add(_Token(_TokType.dot, '.'));
    } else if (m.group(14) != null) {
      tokens.add(_Token(_TokType.ident, m.group(14)!));
    }
  }
  return tokens;
}

/// Evaluates `relevant`/`choiceFilter`/`calculation`/`constraint`
/// expressions against a flat map of current form values.
///
/// [values] should contain the current answers of the SAME group/repeat
/// instance (field name -> String | List<String> | DateTime | num | null).
/// For constraint evaluation, pass the field's own raw value via the special
/// key `'.'`.
class SurveyExpressionEvaluator {
  final Map<String, dynamic> values;
  SurveyExpressionEvaluator(this.values);

  // ---------------- relevant ----------------
  bool evaluateRelevant(String? expr) {
    if (expr == null || expr.trim().isEmpty) return true;
    try {
      final tokens = _tokenize(expr);
      final parser = _BoolParser(tokens, this);
      final result = parser.parseOr();
      return _truthy(result);
    } catch (_) {
      // Fail-open: never hide a field because the parser couldn't
      // understand a rare/unexpected expression shape.
      return true;
    }
  }

  // ---------------- choiceFilter ----------------
  /// Extracts the referenced field name from `filter=${field}` /
  /// `type=${field}` and returns ITS current value, to be passed as
  /// `filterType` into ReferenceDataService.choicesFiltered().
  String? filterValueFor(String? choiceFilterExpr) {
    if (choiceFilterExpr == null) return null;
    final m = RegExp(r'\$\{([a-zA-Z0-9_]+)\}').firstMatch(choiceFilterExpr);
    if (m == null) return null;
    final v = values[m.group(1)!];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  // ---------------- calculation ----------------
  String evaluateCalculation(String? expr) {
    if (expr == null || expr.trim().isEmpty) return '';
    try {
      final tokens = _tokenize(expr);
      final parser = _CalcParser(tokens, this);
      final result = parser.parseValue();
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ---------------- constraint ----------------
  /// [selfValue] is the field's own candidate value (e.g. text currently
  /// being validated).
  bool evaluateConstraint(String? expr, dynamic selfValue) {
    if (expr == null || expr.trim().isEmpty) return true;
    try {
      final tokens = _tokenize(expr);
      if (tokens.length >= 3 &&
          tokens[0].type == _TokType.dot &&
          tokens[1].type == _TokType.op) {
        final op = tokens[1].text;
        final rhs = double.tryParse(tokens[2].text) ?? 0;
        final lhs = double.tryParse(selfValue?.toString() ?? '');
        if (lhs == null) return true; // don't block empty/non-numeric input
        switch (op) {
          case '>':
            return lhs > rhs;
          case '>=':
            return lhs >= rhs;
          case '<':
            return lhs < rhs;
          case '<=':
            return lhs <= rhs;
          case '=':
            return lhs == rhs;
          case '!=':
            return lhs != rhs;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is String) return v.isNotEmpty;
  if (v is num) return v != 0;
  if (v is List) return v.isNotEmpty;
  return true;
}

bool _isSelected(dynamic fieldVal, String target) {
  if (fieldVal == null) return false;
  if (fieldVal is List) {
    return fieldVal.map((e) => e.toString()).contains(target);
  }
  final s = fieldVal.toString();
  if (s.contains(' ')) {
    return s.split(' ').contains(target);
  }
  return s == target;
}

num? _tryNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

String _asStr(dynamic v) => v?.toString() ?? '';

/// Recursive-descent boolean parser for `relevant` expressions.
/// Grammar:
///   orExpr   := andExpr ('or' andExpr)*
///   andExpr  := unary ('and' unary)*
///   unary    := 'not' '(' orExpr ')' | primary
///   primary  := '(' orExpr ')' | 'selected(' field ',' string ')' | comparison
///   comparison := valueExpr [op valueExpr]
class _BoolParser {
  final List<_Token> tokens;
  final SurveyExpressionEvaluator evaluator;
  int _pos = 0;

  _BoolParser(this.tokens, this.evaluator);

  _Token? get _current => _pos < tokens.length ? tokens[_pos] : null;

  _Token _advance() {
    final t = tokens[_pos];
    _pos++;
    return t;
  }

  void _expect(_TokType type) {
    if (_current == null || _current!.type != type) {
      throw FormatException('Expected $type, got ${_current?.type}');
    }
    _advance();
  }

  dynamic parseOr() {
    var left = parseAnd();
    while (_current?.type == _TokType.or) {
      _advance();
      final right = parseAnd();
      left = _truthy(left) || _truthy(right);
    }
    return left;
  }

  dynamic parseAnd() {
    var left = parseUnary();
    while (_current?.type == _TokType.and) {
      _advance();
      final right = parseUnary();
      left = _truthy(left) && _truthy(right);
    }
    return left;
  }

  dynamic parseUnary() {
    if (_current?.type == _TokType.not) {
      _advance();
      _expect(_TokType.lparen);
      final inner = parseOr();
      _expect(_TokType.rparen);
      return !_truthy(inner);
    }
    return parsePrimary();
  }

  dynamic parsePrimary() {
    if (_current?.type == _TokType.lparen) {
      _advance();
      final v = parseOr();
      _expect(_TokType.rparen);
      return v;
    }
    if (_current?.type == _TokType.selected) {
      _advance();
      _expect(_TokType.lparen);
      final fieldTok = _advance();
      _expect(_TokType.comma);
      final valueTok = _advance();
      _expect(_TokType.rparen);
      final fieldVal = evaluator.values[fieldTok.text];
      return _isSelected(fieldVal, valueTok.text);
    }
    final left = _parseValueExpr();
    if (_current?.type == _TokType.op) {
      final opTok = _advance();
      final right = _parseValueExpr();
      return _compare(left, opTok.text, right);
    }
    return left;
  }

  dynamic _parseValueExpr() {
    final tok = _advance();
    switch (tok.type) {
      case _TokType.field:
        return evaluator.values[tok.text];
      case _TokType.string:
        return tok.text;
      case _TokType.number:
        return num.tryParse(tok.text);
      case _TokType.dot:
        return evaluator.values['.'];
      case _TokType.ident:
        return tok.text;
      default:
        throw FormatException('Unexpected token ${tok.text}');
    }
  }

  bool _compare(dynamic left, String op, dynamic right) {
    final ln = _tryNum(left);
    final rn = _tryNum(right);
    if (op == '=') {
      if (ln != null && rn != null) return ln == rn;
      return _asStr(left).trim() == _asStr(right).trim();
    }
    if (op == '!=') {
      if (ln != null && rn != null) return ln != rn;
      return _asStr(left).trim() != _asStr(right).trim();
    }
    final l = ln ?? 0;
    final r = rn ?? 0;
    switch (op) {
      case '>':
        return l > r;
      case '>=':
        return l >= r;
      case '<':
        return l < r;
      case '<=':
        return l <= r;
    }
    return false;
  }
}

/// Recursive-descent parser for `calculation` expressions (concat,
/// format-date, format-date-time, field refs, string literals).
class _CalcParser {
  final List<_Token> tokens;
  final SurveyExpressionEvaluator evaluator;
  int _pos = 0;

  _CalcParser(this.tokens, this.evaluator);

  _Token? get _current => _pos < tokens.length ? tokens[_pos] : null;

  _Token _advance() {
    final t = tokens[_pos];
    _pos++;
    return t;
  }

  void _expect(_TokType type) {
    if (_current == null || _current!.type != type) {
      throw FormatException('Expected $type, got ${_current?.type}');
    }
    _advance();
  }

  dynamic parseValue() {
    final tok = _current;
    if (tok == null) return '';
    if (tok.type == _TokType.ident) {
      final name = tok.text;
      if (name == 'concat') {
        _advance();
        _expect(_TokType.lparen);
        final parts = <String>[];
        parts.add(_asStr(parseValue()));
        while (_current?.type == _TokType.comma) {
          _advance();
          parts.add(_asStr(parseValue()));
        }
        _expect(_TokType.rparen);
        return parts.join();
      }
      if (name == 'format-date' || name == 'format-date-time') {
        _advance();
        _expect(_TokType.lparen);
        final dateVal = parseValue();
        _expect(_TokType.comma);
        final fmtTok = _advance(); // string
        _expect(_TokType.rparen);
        return _formatDate(dateVal, fmtTok.text);
      }
      // Unknown function/identifier: treat as literal text.
      _advance();
      return name;
    }
    if (tok.type == _TokType.field) {
      _advance();
      return evaluator.values[tok.text];
    }
    if (tok.type == _TokType.string) {
      _advance();
      return tok.text;
    }
    if (tok.type == _TokType.number) {
      _advance();
      return tok.text;
    }
    _advance();
    return tok.text;
  }

  String _formatDate(dynamic value, String fmt) {
    DateTime? dt;
    if (value is DateTime) {
      dt = value;
    } else if (value is String && value.isNotEmpty) {
      dt = DateTime.tryParse(value);
    }
    dt ??= DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    var out = fmt;
    out = out.replaceAll('%Y', dt.year.toString());
    out = out.replaceAll('%y', two(dt.year % 100));
    out = out.replaceAll('%m', two(dt.month));
    out = out.replaceAll('%d', two(dt.day));
    out = out.replaceAll('%H', two(dt.hour));
    out = out.replaceAll('%M', two(dt.minute));
    out = out.replaceAll('%S', two(dt.second));
    return out;
  }
}
