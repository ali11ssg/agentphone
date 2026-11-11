/// The Computer panel's model: what the agent did, in the shape the panel
/// shows it.
///
/// The panel is a view over the session's tool calls, not a second source of
/// truth: every entry here is derived from a [ToolState] the server sent, so
/// the panel and the chat never disagree about what happened.
///
/// The panel groups the tool calls into four tabs:
///  - Terminal: shell commands, with the whole command line, the working
///    directory, the times, the exit code and the output;
///  - Files: the files the agent wrote or edited;
///  - Plan: the task list the agent keeps;
///  - Browser: the pages the agent fetched.
library;

import 'models.dart';
import 'permission_risk.dart' show isRiskyCommand;

/// What kind of thing a [ComputerEvent] is.
enum ComputerEventKind { command, edit, plan, page }

/// One thing the agent did.
class ComputerEvent {
  const ComputerEvent({
    required this.kind,
    required this.title,
    this.command,
    this.workingDirectory,
    this.output,
    this.exitCode,
    this.startedAt,
    this.completedAt,
    this.running = false,
    this.risky = false,
  });

  final ComputerEventKind kind;

  /// The short line the panel shows as the entry's title.
  final String title;

  /// The whole command line, for a shell call. Never shortened: the panel is
  /// where a command is read in full.
  final String? command;

  /// The directory the command ran in.
  final String? workingDirectory;

  /// What the command printed.
  final String? output;

  /// The exit code, when the server reported one.
  final int? exitCode;

  final DateTime? startedAt;
  final DateTime? completedAt;

  /// True while the server says the call is still running.
  final bool running;

  /// True for a command that changes something outside the project.
  final bool risky;

  /// How long the call took, when both ends are known.
  Duration? get duration {
    final start = startedAt;
    final end = completedAt;
    if (start == null || end == null) return null;
    final value = end.difference(start);
    return value.isNegative ? null : value;
  }

  /// True when the call finished with a non-zero exit code.
  bool get failed => exitCode != null && exitCode != 0;
}

/// The whole panel: the events in the order they happened.
class ComputerPanelModel {
  const ComputerPanelModel(this.events);

  const ComputerPanelModel.empty() : events = const [];

  final List<ComputerEvent> events;

  List<ComputerEvent> get commands => _ofKind(ComputerEventKind.command);

  List<ComputerEvent> get edits => _ofKind(ComputerEventKind.edit);

  List<ComputerEvent> get plan => _ofKind(ComputerEventKind.plan);

  List<ComputerEvent> get pages => _ofKind(ComputerEventKind.page);

  List<ComputerEvent> _ofKind(ComputerEventKind kind) =>
      events.where((event) => event.kind == kind).toList(growable: false);

  /// The newest event, the one the collapsed panel speaks about.
  ComputerEvent? get latest => events.isEmpty ? null : events.last;

  /// True while something is still running.
  bool get busy => events.any((event) => event.running);

  /// One line for the collapsed panel: what the agent is doing right now.
  String statusLine() {
    final last = latest;
    if (last == null) return '';
    if (last.running) return last.title;
    return last.title;
  }
}

/// The tool calls of a session, in the panel's shape.
///
/// The server names the tools; this reads the same names the chat's tool
/// cards read, so both views say the same thing.
List<ComputerEvent> computerEventsFromToolStates(
  Iterable<ToolState> states, {
  Iterable<String> toolNames = const <String>[],
}) {
  final names = toolNames.toList(growable: false);
  final events = <ComputerEvent>[];
  var index = 0;
  for (final state in states) {
    final name = (index < names.length ? names[index] : '').toLowerCase();
    index++;
    final event = _eventFor(name, state);
    if (event != null) events.add(event);
  }
  return events;
}

ComputerEvent? _eventFor(String name, ToolState state) {
  final input = state.input;
  final metadata = state.metadata;
  final running = state.status == 'running' || state.status == 'pending';
  final startedAt = state.startedAt;
  final completedAt = state.completedAt;

  switch (name) {
    case 'bash':
    case 'shell':
    case 'run':
    case 'terminal':
      final command = _string(input['command']) ?? _string(input['cmd']);
      if (command == null || command.trim().isEmpty) return null;
      return ComputerEvent(
        kind: ComputerEventKind.command,
        title: command.trim(),
        command: command,
        workingDirectory:
            _string(input['workdir']) ??
            _string(input['cwd']) ??
            _string(input['directory']),
        output: state.output,
        exitCode: _number(metadata?['exit'])?.toInt() ??
            _number(metadata?['exitCode'])?.toInt(),
        startedAt: startedAt,
        completedAt: completedAt,
        running: running,
        risky: isRiskyCommand(command),
      );
    case 'edit':
    case 'write':
    case 'patch':
    case 'apply_patch':
      final path =
          _string(input['filePath']) ??
          _string(input['file_path']) ??
          _string(input['path']);
      return ComputerEvent(
        kind: ComputerEventKind.edit,
        title: path ?? state.title ?? name,
        command: path,
        workingDirectory: _string(input['workdir']),
        startedAt: startedAt,
        completedAt: completedAt,
        running: running,
      );
    case 'todowrite':
    case 'todo':
      return ComputerEvent(
        kind: ComputerEventKind.plan,
        title: state.title ?? 'Plan',
        output: _planText(metadata?['todos'] ?? input['todos']),
        startedAt: startedAt,
        completedAt: completedAt,
        running: running,
      );
    case 'webfetch':
    case 'browser':
    case 'websearch':
      final url = _string(input['url']) ?? _string(input['query']);
      if (url == null) return null;
      return ComputerEvent(
        kind: ComputerEventKind.page,
        title: url,
        command: url,
        output: state.output,
        startedAt: startedAt,
        completedAt: completedAt,
        running: running,
      );
    default:
      return null;
  }
}

/// The task list, as one line per task.
String? _planText(Object? todos) {
  if (todos is! List) return null;
  final lines = <String>[];
  for (final todo in todos) {
    if (todo is! Map) continue;
    final content = _string(todo['content']) ?? _string(todo['title']);
    if (content == null) continue;
    final status = _string(todo['status']) ?? 'pending';
    lines.add('[$status] $content');
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

String? _string(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

num? _number(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

/// The panel's model for one conversation: every tool call the server
/// reported, in the order it reported them.
ComputerPanelModel computerPanelModelFromMessages(
  Iterable<MessageWithParts> messages,
) {
  final events = <ComputerEvent>[];
  for (final message in messages) {
    for (final part in message.parts) {
      if (part.type != 'tool') continue;
      final name = (part.toolName ?? '').toLowerCase();
      final event = _eventFor(name, part.toolState);
      if (event != null) events.add(event);
    }
  }
  return ComputerPanelModel(events);
}
