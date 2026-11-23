import 'package:app_module_api/app_module_api.dart';
import 'package:flutter/material.dart';

import '../logic.dart';
import 'update_localizations.dart';
import 'update_page.dart';
import 'update_transfer_feedback.dart';
import 'update_view_model.dart';

/// The host owns this module instance and its navigation callback.
final class UpdateModule implements AppModule, SettingsContributor {
  UpdateModule({
    required UpdateRepository repository,
    required this.navigateToUpdate,
    OpenUpdate? openUpdate,
  }) : _repository = repository,
       _openUpdate = openUpdate;

  final UpdateRepository _repository;
  final OpenUpdate? _openUpdate;
  final void Function(BuildContext) navigateToUpdate;

  UpdateViewModel? _viewModel;

  @override
  String get id => 'app_update';

  @override
  List<LocalizationsDelegate<dynamic>> get localizationsDelegates => const [
    UpdateLocalizations.delegate,
  ];

  @override
  List<Locale> get supportedLocales => UpdateLocalizations.supportedLocales;

  @override
  List<SettingsEntry> get settingsEntries => [
    SettingsEntry(
      id: 'app_update.check',
      builder: (context) {
        final strings = UpdateLocalizations.of(context);
        return ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(strings.title),
          subtitle: Text(strings.settingsDescription),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => navigateToUpdate(context),
        );
      },
    ),
  ];

  @override
  Future<void> init() async {
    if (_viewModel != null) {
      throw StateError('Update module already initialized.');
    }
    _viewModel = UpdateViewModel(
      repository: _repository,
      openUpdate: _openUpdate,
    );
  }

  Widget buildPage(
    BuildContext context, {
    String? appName,
    String? subtitle,
    Widget? appIcon,
    UpdateTransferFeedback? transfer,
  }) {
    final viewModel = _viewModel;
    if (viewModel == null) {
      throw StateError('Initialize UpdateModule first.');
    }
    return UpdatePage(
      viewModel: viewModel,
      appName: appName,
      subtitle: subtitle,
      appIcon: appIcon,
      transfer: transfer,
    );
  }

  @override
  Future<void> dispose() async {
    final viewModel = _viewModel;
    _viewModel = null;
    viewModel?.dispose();
  }
}
