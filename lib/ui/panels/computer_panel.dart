/// The Computer panel: a bottom panel that follows the agent.
///
/// Three states, one gesture: collapsed (one line of status), half (the
/// usual working height) and full (everything the agent did). The panel never
/// hides what happened: the terminal tab shows the whole command line, the
/// directory it ran in, when it ran, how it ended and what it printed.
///
/// Everything the panel shows is masked with [KitRedact] before it is drawn,
/// so a key that appears in a command or in an output never reaches the
/// screen, the clipboard or a screenshot.
library;

import 'package:flutter/material.dart';

import '../../domain/computer_panel.dart';
import '../../l10n/app_localizations.dart';
import '../app_iconography.dart';
import '../kit/kit_redact.dart';
import '../kit/kit_tokens.dart';
import '../theme_roles.dart';

/// How much of the screen the panel takes.
enum ComputerPanelSize { collapsed, half, full }

/// The panel itself.
class ComputerPanel extends StatefulWidget {
  const ComputerPanel({
    super.key,
    required this.model,
    this.onTakeOver,
    this.onOpenTerminal,
    this.onOpenFiles,
  });

  /// What the agent did, newest last.
  final ComputerPanelModel model;

  /// Called when the person takes over: the agent is stopped, and the panel
  /// hands the screen back to them.
  final Future<void> Function()? onTakeOver;

  /// Opens the full terminal screen.
  final VoidCallback? onOpenTerminal;

  /// Opens the files screen.
  final VoidCallback? onOpenFiles;

  @override
  State<ComputerPanel> createState() => _ComputerPanelState();
}

class _ComputerPanelState extends State<ComputerPanel> {
  ComputerPanelSize _size = ComputerPanelSize.collapsed;
  int _tab = 0;

  static const _tabs = [
    ComputerEventKind.command,
    ComputerEventKind.edit,
    ComputerEventKind.plan,
    ComputerEventKind.page,
  ];

  double _heightFor(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    return switch (_size) {
      ComputerPanelSize.collapsed => 74,
      ComputerPanelSize.half => screen * 0.46,
      ComputerPanelSize.full => screen * 0.92,
    };
  }

  void _cycleSize() {
    setState(() {
      _size = switch (_size) {
        ComputerPanelSize.collapsed => ComputerPanelSize.half,
        ComputerPanelSize.half => ComputerPanelSize.full,
        ComputerPanelSize.full => ComputerPanelSize.collapsed,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final roles = ThemeRoles.of(context);
    final tokens = KitTokens.of(context);
    final model = widget.model;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _heightFor(context),
      decoration: BoxDecoration(
        color: roles.surface1,
        border: Border(top: BorderSide(color: roles.hairline)),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.sheetRadius),
        ),
      ),
      child: Column(
        children: [
          _header(context, roles, tokens, model),
          if (_size != ComputerPanelSize.collapsed)
            Expanded(child: _body(context, roles, tokens, model)),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    final latest = model.latest;
    return Padding(
      padding: EdgeInsets.only(
        left: tokens.space4,
        right: tokens.space2,
        top: tokens.space2,
        bottom: tokens.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIconography.terminal,
                size: 18,
                color: roles.text2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latest == null
                      ? l10n.computerPanelIdle
                      : KitRedact.text(latest.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: roles.text1, fontSize: 13),
                ),
              ),
              if (model.busy && widget.onTakeOver != null)
                TextButton(
                  key: const ValueKey('computer-panel-take-over'),
                  onPressed: () => widget.onTakeOver!(),
                  child: Text(l10n.computerPanelTakeOver),
                ),
              IconButton(
                key: const ValueKey('computer-panel-size'),
                onPressed: _cycleSize,
                icon: Icon(
                  _size == ComputerPanelSize.full
                      ? AppIconography.chevronDown
                      : AppIconography.chevronUp,
                  size: 20,
                  color: roles.text2,
                ),
              ),
            ],
          ),
          if (_size != ComputerPanelSize.collapsed)
            Row(
              children: [
                for (var index = 0; index < _tabs.length; index++)
                  _tabButton(context, roles, tokens, model, index),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tabButton(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
    int index,
  ) {
    final kind = _tabs[index];
    final count = switch (kind) {
      ComputerEventKind.command => model.commands.length,
      ComputerEventKind.edit => model.edits.length,
      ComputerEventKind.plan => model.plan.length,
      ComputerEventKind.page => model.pages.length,
    };
    final selected = _tab == index;
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    final label = switch (kind) {
      ComputerEventKind.command => l10n.computerPanelTabTerminal,
      ComputerEventKind.edit => l10n.computerPanelTabFiles,
      ComputerEventKind.plan => l10n.computerPanelTabPlan,
      ComputerEventKind.page => l10n.computerPanelTabBrowser,
    };
    return Padding(
      padding: EdgeInsets.only(right: tokens.space2),
      child: TextButton(
        key: ValueKey('computer-panel-tab-$index'),
        onPressed: () => setState(() => _tab = index),
        style: TextButton.styleFrom(
          foregroundColor: selected ? roles.accent : roles.text2,
          padding: EdgeInsets.symmetric(horizontal: tokens.space2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(count == 0 ? label : '$label · $count'),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final kind = _tabs[_tab];
    return switch (kind) {
      ComputerEventKind.command => _terminalTab(context, roles, tokens, model),
      ComputerEventKind.edit => _editsTab(context, roles, tokens, model),
      ComputerEventKind.plan => _planTab(context, roles, tokens, model),
      ComputerEventKind.page => _pagesTab(context, roles, tokens, model),
    };
  }

  Widget _terminalTab(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final commands = model.commands;
    if (commands.isEmpty) return _empty(context, roles);
    return ListView.builder(
      key: const ValueKey('computer-panel-terminal-list'),
      padding: EdgeInsets.fromLTRB(
        tokens.space3,
        tokens.space2,
        tokens.space3,
        tokens.space4,
      ),
      itemCount: commands.length,
      itemBuilder: (context, index) {
        final event = commands[commands.length - 1 - index];
        return _commandEntry(context, roles, tokens, event);
      },
    );
  }

  Widget _commandEntry(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerEvent event,
  ) {
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    final output = event.output;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.risky)
                Padding(
                  padding: EdgeInsets.only(right: tokens.space1),
                  child: Icon(
                    AppIconography.warning,
                    size: 16,
                    color: roles.attention,
                  ),
                ),
              Expanded(
                child: SelectableText(
                  KitRedact.text(event.command ?? event.title),
                  style: TextStyle(
                    color: roles.text1,
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space1),
          Text(
            _metaLine(l10n, event),
            style: TextStyle(color: roles.text3, fontSize: 11.5),
          ),
          if (output != null && output.trim().isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: tokens.space1),
              padding: EdgeInsets.all(tokens.space2),
              decoration: BoxDecoration(
                color: roles.surface2,
                borderRadius: BorderRadius.circular(tokens.panelRadius),
              ),
              child: SelectableText(
                KitRedact.text(_trimOutput(output)),
                style: TextStyle(
                  color: roles.text2,
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _metaLine(AppLocalizations l10n, ComputerEvent event) {
    final parts = <String>[];
    final directory = event.workingDirectory;
    if (directory != null && directory.isNotEmpty) parts.add(directory);
    final started = event.startedAt;
    if (started != null) {
      final hh = started.hour.toString().padLeft(2, '0');
      final mm = started.minute.toString().padLeft(2, '0');
      final ss = started.second.toString().padLeft(2, '0');
      parts.add('$hh:$mm:$ss');
    }
    final duration = event.duration;
    if (duration != null) {
      parts.add('${duration.inSeconds}s');
    }
    if (event.running) {
      parts.add(l10n.computerPanelRunning);
    } else if (event.exitCode != null) {
      parts.add('exit ${event.exitCode}');
    }
    return parts.join(' · ');
  }

  Widget _editsTab(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final edits = model.edits;
    if (edits.isEmpty) return _empty(context, roles);
    return ListView.builder(
      key: const ValueKey('computer-panel-files-list'),
      padding: EdgeInsets.fromLTRB(
        tokens.space3,
        tokens.space2,
        tokens.space3,
        tokens.space4,
      ),
      itemCount: edits.length,
      itemBuilder: (context, index) {
        final event = edits[edits.length - 1 - index];
        return ListTile(
          key: ValueKey('computer-panel-file-$index'),
          dense: true,
          leading: Icon(
            AppIconography.file,
            size: 18,
            color: roles.text2,
          ),
          title: Text(
            KitRedact.text(event.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: roles.text1, fontSize: 12.5),
          ),
          onTap: widget.onOpenFiles,
        );
      },
    );
  }

  Widget _planTab(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final plan = model.plan;
    if (plan.isEmpty) return _empty(context, roles);
    final last = plan.last;
    final text = last.output ?? '';
    return ListView(
      key: const ValueKey('computer-panel-plan-list'),
      padding: EdgeInsets.fromLTRB(
        tokens.space3,
        tokens.space2,
        tokens.space3,
        tokens.space4,
      ),
      children: [
        SelectableText(
          KitRedact.text(text),
          style: TextStyle(
            color: roles.text1,
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _pagesTab(
    BuildContext context,
    ThemeRoles roles,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final pages = model.pages;
    if (pages.isEmpty) return _empty(context, roles);
    return ListView.builder(
      key: const ValueKey('computer-panel-browser-list'),
      padding: EdgeInsets.fromLTRB(
        tokens.space3,
        tokens.space2,
        tokens.space3,
        tokens.space4,
      ),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final event = pages[pages.length - 1 - index];
        return ListTile(
          key: ValueKey('computer-panel-page-$index'),
          dense: true,
          leading: Icon(
            AppIconography.browser,
            size: 18,
            color: roles.text2,
          ),
          title: Text(
            KitRedact.text(event.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: roles.text1, fontSize: 12.5),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context, ThemeRoles roles) {
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    return Center(
      child: Text(
        l10n.computerPanelEmpty,
        style: TextStyle(color: roles.text3, fontSize: 12.5),
      ),
    );
  }
}

/// Keeps the tail of a long output: the last lines are the ones that say what
/// happened, and ten thousand lines in memory is more than a phone needs.
String _trimOutput(String output, {int maxLines = 200}) {
  final lines = output.split('\n');
  if (lines.length <= maxLines) return output;
  final kept = lines.sublist(lines.length - maxLines);
  return kept.join('\n');
}

/// Opens the Computer panel over the conversation.
///
/// The panel is a sheet, so the conversation behind it stays readable and the
/// person can dismiss it with one tap outside. Nothing is fetched here: the
/// model is what the session already said.
Future<void> showComputerPanel(
  BuildContext context, {
  required ComputerPanelModel model,
  Future<void> Function()? onTakeOver,
  VoidCallback? onOpenTerminal,
  VoidCallback? onOpenFiles,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: ComputerPanel(
        model: model,
        onTakeOver: onTakeOver,
        onOpenTerminal: onOpenTerminal,
        onOpenFiles: onOpenFiles,
      ),
    ),
  );
}
