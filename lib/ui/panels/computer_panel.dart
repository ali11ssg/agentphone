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
///
/// The panel is built from the kit only (kit-v2 §9): no framework text, icon,
/// button or row is constructed here.
library;

import 'package:flutter/material.dart';

import '../../domain/computer_panel.dart';
import '../../l10n/app_localizations.dart';
import '../app_iconography.dart';
import '../kit/kit.dart';

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
    final tokens = KitTokens.of(context);
    final model = widget.model;

    return SizedBox(
      height: _heightFor(context),
      child: KitPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _header(context, tokens, model),
            if (_size != ComputerPanelSize.collapsed)
              Expanded(child: _body(context, tokens, model)),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    final latest = model.latest;
    return Padding(
      padding: EdgeInsets.only(
        left: tokens.space4,
        right: tokens.space1,
        top: tokens.space2,
        bottom: tokens.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KitIcon(
                AppIconography.terminal,
                size: KitIconSize.small,
                tone: KitTextTone.secondary,
              ),
              SizedBox(width: tokens.space2),
              Expanded(
                child: KitText(
                  latest == null
                      ? l10n.computerPanelIdle
                      : KitRedact.text(latest.title),
                  role: KitTextRole.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (model.busy && widget.onTakeOver != null)
                KitButton.tertiary(
                  key: const ValueKey('computer-panel-take-over'),
                  label: l10n.computerPanelTakeOver,
                  onPressed: () => widget.onTakeOver!(),
                ),
              KitIconButton(
                key: const ValueKey('computer-panel-size'),
                tooltip: l10n.computerPanelOpen,
                icon: _size == ComputerPanelSize.full
                    ? AppIconography.chevronDown
                    : AppIconography.chevronUp,
                onPressed: _cycleSize,
                size: 20,
                quiet: true,
              ),
            ],
          ),
          if (_size != ComputerPanelSize.collapsed)
            Row(
              children: [
                for (var index = 0; index < _tabs.length; index++)
                  _tabButton(context, tokens, model, index),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tabButton(
    BuildContext context,
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
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    final label = switch (kind) {
      ComputerEventKind.command => l10n.computerPanelTabTerminal,
      ComputerEventKind.edit => l10n.computerPanelTabFiles,
      ComputerEventKind.plan => l10n.computerPanelTabPlan,
      ComputerEventKind.page => l10n.computerPanelTabBrowser,
    };
    return Padding(
      padding: EdgeInsets.only(right: tokens.space2),
      child: KitButton.tertiary(
        key: ValueKey('computer-panel-tab-$index'),
        label: count == 0 ? label : '$label · $count',
        onPressed: () => setState(() => _tab = index),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final kind = _tabs[_tab];
    return switch (kind) {
      ComputerEventKind.command => _terminalTab(context, tokens, model),
      ComputerEventKind.edit => _editsTab(context, tokens, model),
      ComputerEventKind.plan => _planTab(context, tokens, model),
      ComputerEventKind.page => _pagesTab(context, tokens, model),
    };
  }

  EdgeInsets _listPadding(KitTokens tokens) => EdgeInsets.fromLTRB(
    tokens.space3,
    tokens.space2,
    tokens.space3,
    tokens.space4,
  );

  Widget _terminalTab(
    BuildContext context,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final commands = model.commands;
    if (commands.isEmpty) return _empty(context);
    return ListView.builder(
      key: const ValueKey('computer-panel-terminal-list'),
      padding: _listPadding(tokens),
      itemCount: commands.length,
      itemBuilder: (context, index) {
        final event = commands[commands.length - 1 - index];
        return _commandEntry(context, tokens, event);
      },
    );
  }

  Widget _commandEntry(
    BuildContext context,
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
                  child: const KitIcon(
                    AppIconography.warning,
                    size: KitIconSize.small,
                    tone: KitTextTone.attention,
                  ),
                ),
              Expanded(
                child: KitText.mono(
                  KitRedact.text(event.command ?? event.title),
                  selectable: true,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space1),
          KitText(
            _metaLine(l10n, event),
            role: KitTextRole.caption,
            tone: KitTextTone.tertiary,
          ),
          if (output != null && output.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: tokens.space1),
              child: KitPanel(
                padding: EdgeInsets.all(tokens.space2),
                child: KitText.mono(
                  KitRedact.text(_trimOutput(output)),
                  selectable: true,
                  tone: KitTextTone.secondary,
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
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final edits = model.edits;
    if (edits.isEmpty) return _empty(context);
    return ListView.builder(
      key: const ValueKey('computer-panel-files-list'),
      padding: _listPadding(tokens),
      itemCount: edits.length,
      itemBuilder: (context, index) {
        final event = edits[edits.length - 1 - index];
        return KitRow(
          key: ValueKey('computer-panel-file-$index'),
          leading: const KitIcon(
            AppIconography.file,
            size: KitIconSize.small,
            tone: KitTextTone.secondary,
          ),
          title: KitRedact.text(event.title),
          titleMaxLines: 2,
          onTap: widget.onOpenFiles,
        );
      },
    );
  }

  Widget _planTab(
    BuildContext context,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final plan = model.plan;
    if (plan.isEmpty) return _empty(context);
    final last = plan.last;
    final text = last.output ?? '';
    return ListView(
      key: const ValueKey('computer-panel-plan-list'),
      padding: _listPadding(tokens),
      children: [
        KitText.mono(KitRedact.text(text), selectable: true),
      ],
    );
  }

  Widget _pagesTab(
    BuildContext context,
    KitTokens tokens,
    ComputerPanelModel model,
  ) {
    final pages = model.pages;
    if (pages.isEmpty) return _empty(context);
    return ListView.builder(
      key: const ValueKey('computer-panel-browser-list'),
      padding: _listPadding(tokens),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final event = pages[pages.length - 1 - index];
        return KitRow(
          key: ValueKey('computer-panel-page-$index'),
          leading: const KitIcon(
            AppIconography.browser,
            size: KitIconSize.small,
            tone: KitTextTone.secondary,
          ),
          title: KitRedact.text(event.title),
          titleMaxLines: 2,
          onTap: widget.onOpenTerminal,
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final l10n = lookupAppLocalizations(Localizations.localeOf(context));
    return Center(
      child: KitText(
        l10n.computerPanelEmpty,
        role: KitTextRole.secondary,
        tone: KitTextTone.tertiary,
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
  final l10n = lookupAppLocalizations(Localizations.localeOf(context));
  return showKitSheet<void>(
    context,
    title: l10n.computerPanelOpen,
    height: KitSheetHeight.full,
    body: (context) => ComputerPanel(
      model: model,
      onTakeOver: onTakeOver,
      onOpenTerminal: onOpenTerminal,
      onOpenFiles: onOpenFiles,
    ),
  );
}
