import 'package:flutter/material.dart';

import '../logic.dart';
import 'update_localizations.dart';
import 'update_transfer_feedback.dart';
import 'update_view_model.dart';

/// Default update content. The host supplies the route's app bar and app mark.
final class UpdatePage extends StatelessWidget {
  const UpdatePage({
    required this.viewModel,
    this.appName,
    this.subtitle,
    this.appIcon,
    this.transfer,
    super.key,
  });

  final UpdateViewModel viewModel;
  final String? appName;
  final String? subtitle;
  final Widget? appIcon;
  final UpdateTransferFeedback? transfer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final theme = Theme.of(context);
      final strings = UpdateLocalizations.of(context);
      final version = viewModel.installedVersion;
      final checking = viewModel.status == UpdateCheckStatus.checking;
      final checkMessage = switch (viewModel.status) {
        UpdateCheckStatus.checking => strings.checking,
        UpdateCheckStatus.current => strings.current,
        UpdateCheckStatus.failed => strings.failure(viewModel.failure!),
        _ => strings.checkDescription(version.platform),
      };
      return SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          children: [
            if (appName != null || appIcon != null || subtitle != null) ...[
              Center(
                child: Column(
                  children: [
                    if (appIcon case final icon?) ...[
                      icon,
                      const SizedBox(height: 16),
                    ],
                    if (appName case final name?)
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                    if (subtitle case final description?) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(strings.installedVersion),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 128),
                      child: Text(
                        '${version.versionName} (${version.buildNumber})',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: Text(strings.check),
                    subtitle: Semantics(
                      liveRegion: true,
                      child: Text(checkMessage),
                    ),
                    trailing: checking
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: viewModel.isBusy ? null : viewModel.check,
                  ),
                ],
              ),
            ),
            if (viewModel.candidate case final candidate?) ...[
              const SizedBox(height: 16),
              _releaseCard(context, strings, candidate),
            ],
          ],
        ),
      );
    },
  );

  Widget _releaseCard(
    BuildContext context,
    UpdateLocalizations strings,
    UpdateCandidate candidate,
  ) {
    final theme = Theme.of(context);
    final notes = candidate.manifest.releaseNotesFor(
      strings.locale.toLanguageTag(),
    );
    final opening = viewModel.actionStatus == UpdateActionStatus.opening;
    final progress = transfer;
    final phase = progress?.phase;
    final actionMessage =
        progress?.message ??
        switch (viewModel.actionStatus) {
          UpdateActionStatus.idle => null,
          UpdateActionStatus.opening =>
            phase == null
                ? strings.opening
                : strings.phase(phase, progress?.fraction),
          UpdateActionStatus.opened => strings.opened,
          UpdateActionStatus.failed => strings.openFailed,
        };
    final failed =
        progress?.failed ?? viewModel.actionStatus == UpdateActionStatus.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                strings.available(candidate.manifest.versionName),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              strings.artifactType(candidate.artifact.platform),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (candidate.required) Text(strings.required),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .34,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('· $note'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (opening && phase != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: phase == UpdateTransferPhase.downloading
                    ? progress?.fraction
                    : null,
              ),
            ],
            if (actionMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    actionMessage,
                    style: failed
                        ? TextStyle(color: theme.colorScheme.error)
                        : theme.textTheme.bodySmall,
                  ),
                ),
              ),
            if (viewModel.canOpenUpdate) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: viewModel.isBusy ? null : viewModel.openUpdate,
                icon: opening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt),
                label: Text(
                  opening
                      ? strings.opening
                      : progress?.paused == true
                      ? strings.resume
                      : failed
                      ? strings.retry
                      : strings.open,
                ),
              ),
            ],
            if (opening &&
                phase == UpdateTransferPhase.downloading &&
                progress?.onPause != null)
              TextButton(
                onPressed: progress!.onPause,
                child: Text(strings.pause),
              ),
          ],
        ),
      ),
    );
  }
}
