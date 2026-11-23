import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'identity_controller.dart';
import 'identity_failure.dart';
import 'identity_models.dart';

String identityText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// Account preferences belong to the host. Persist passwords only in its secure store.
abstract interface class IdentitySavedLogins {
  Future<List<String>> accounts();
  Future<String?> passwordFor(String account);
  Future<void> remember(String account, {String? password});
  Future<void> forget(String account);
}

final class IdentityAccountTile extends StatelessWidget {
  const IdentityAccountTile({
    required this.controller,
    required this.onTap,
    this.leading,
    super.key,
  });

  final IdentityController controller;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListTile(
      leading: leading ?? const Icon(Icons.account_circle_outlined),
      title: Text(identityText(context, '账号', 'Account')),
      subtitle: Text(
        controller.user?.displayName ?? identityText(context, '登录', 'Sign in'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

final class IdentityPage extends StatefulWidget {
  const IdentityPage({
    required this.controller,
    this.signInHelp,
    this.serviceAddress,
    this.onSaveServiceAddress,
    this.savedLogins,
    this.onRename,
    super.key,
  });

  final IdentityController controller;
  final Widget? signInHelp;
  final String? serviceAddress;
  final Future<void> Function(String address)? onSaveServiceAddress;
  final IdentitySavedLogins? savedLogins;

  /// The host updates the profile. The page then reloads the verified identity.
  final Future<void> Function(String name)? onRename;

  @override
  State<IdentityPage> createState() => _IdentityPageState();
}

final class _IdentityPageState extends State<IdentityPage> {
  final _form = GlobalKey<FormState>();
  final _serviceAddress = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  List<String> _saved = const [];
  String? _prefilledAccount;
  bool _showPassword = false;
  bool _otpShown = false;
  bool _savePassword = false;
  bool _savingAddress = false;
  bool _editingProfile = false;
  bool _canceling = false;
  int _operation = 0;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _serviceAddress.text = widget.serviceAddress ?? '';
    unawaited(_loadSaved());
  }

  @override
  void dispose() {
    unawaited(Future<void>.microtask(widget.controller.cancelSignIn));
    _serviceAddress.dispose();
    _username.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  String _text(String zh, String en) => identityText(context, zh, en);

  Future<void> _loadSaved() async {
    final store = widget.savedLogins;
    if (store == null) return;
    try {
      final accounts = await store.accounts();
      if (mounted) setState(() => _saved = accounts);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = _text('无法读取已保存账号。', 'Could not load saved accounts.'),
        );
      }
    }
  }

  Future<void> _selectSaved(String username) async {
    final previous = _username.text;
    final previousPassword = _password.text;
    try {
      final password = await widget.savedLogins!.passwordFor(username);
      if (!mounted ||
          _username.text != previous ||
          _password.text != previousPassword ||
          widget.controller.busy) {
        return;
      }
      _username.text = username;
      _password.text = password ?? '';
      _prefilledAccount = password == null ? null : username;
      setState(() => _savePassword = password != null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = _text('无法读取已保存账号。', 'Could not load saved account.'),
        );
      }
    }
  }

  Future<void> _forgetSaved(String username) async {
    try {
      await widget.savedLogins!.forget(username);
      if (!mounted) return;
      if (_username.text == username) {
        _password.clear();
        setState(() => _savePassword = false);
      }
      await _loadSaved();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = _text(
            '无法移除已保存账号。',
            'Could not remove the saved account.',
          ),
        );
      }
    }
  }

  Future<void> _saveAddress() async {
    final action = widget.onSaveServiceAddress;
    if (action == null || _savingAddress || widget.controller.busy) return;
    setState(() {
      _savingAddress = true;
      _notice = null;
    });
    try {
      await action(_serviceAddress.text.trim());
      if (!mounted) return;
      _username.clear();
      _clearSecrets();
      _savePassword = false;
      await _loadSaved();
    } catch (_) {
      if (mounted) {
        _notice = _text(
          '服务地址未保存，请检查后重试。',
          'Could not save the service address. Check it and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  Future<void> _submit() async {
    final controller = widget.controller;
    if (controller.busy ||
        _savingAddress ||
        _canceling ||
        _form.currentState?.validate() != true) {
      return;
    }
    final operation = ++_operation;
    final username = _username.text.trim();
    final password = _password.text;
    final savePassword = _savePassword;
    setState(() => _notice = null);
    await controller.signIn(
      account: username,
      password: password,
      otp: _otpShown ? _otp.text.trim() : null,
    );
    if (!mounted || _operation != operation) return;
    final code = controller.failure?.code;
    setState(() {
      _otpShown =
          code == IdentityFailureCode.otpRequired ||
          code == IdentityFailureCode.invalidOtp;
      if (controller.isVerified) _savePassword = false;
    });
    if (!_otpShown) _clearSecrets();
    if (!controller.isVerified) return;
    _username.clear();
    TextInput.finishAutofillContext(shouldSave: false);
    try {
      await widget.savedLogins?.remember(
        username,
        password: savePassword ? password : null,
      );
      if (mounted) await _loadSaved();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = _text(
            '已登录，登录信息未保存。',
            'Signed in. Login details were not saved.',
          ),
        );
      }
    }
  }

  void _clearSecrets() {
    _password.clear();
    _otp.clear();
    _prefilledAccount = null;
    _showPassword = false;
  }

  Future<void> _cancelLogin() async {
    if (_canceling) return;
    ++_operation;
    _clearSecrets();
    setState(() {
      _canceling = true;
      _otpShown = false;
    });
    try {
      await widget.controller.cancelSignIn();
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  Future<void> _editNickname(String current) async {
    final rename = widget.onRename;
    if (rename == null || _editingProfile) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(current: current),
    );
    if (!mounted || name == null || !widget.controller.isVerified) return;
    setState(() {
      _editingProfile = true;
      _notice = null;
    });
    try {
      await rename(name);
      if (mounted && widget.controller.isVerified) {
        await widget.controller.restore();
      }
    } catch (_) {
      if (mounted) {
        _notice = _text('昵称保存失败，请重试。', 'Could not save nickname. Retry.');
      }
    } finally {
      if (mounted) setState(() => _editingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_text('账号', 'Account'))),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= 1000 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1180 : 600),
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [_accountCard(widget.controller.state)],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _accountCard(IdentityState state) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = state.user;
    final name = user?.displayName ?? user?.email ?? user?.id;
    final signingIn =
        state.status == IdentityStatus.signingIn ||
        state.status == IdentityStatus.verifying;
    final busy =
        state.isBusy || _savingAddress || _editingProfile || _canceling;
    final offline = state.status == IdentityStatus.offlineCached;
    final formEnabled = !busy && !state.localCleanupRequired;
    final message = _notice ?? _failureMessage(state);
    final decoration = InputDecoration(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: colors.secondaryContainer,
                    foregroundColor: colors.onSecondaryContainer,
                    child: const Icon(Icons.person_outline_rounded, size: 30),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  name ?? _text('登录账号', 'Sign in'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  offline
                      ? _text(
                          '当前离线，联网后可重新连接。',
                          'You are offline. Reconnect when online.',
                        )
                      : state.isVerified
                      ? _text('已登录', 'Signed in')
                      : state.status == IdentityStatus.restoring
                      ? _text('正在恢复会话…', 'Restoring the session…')
                      : _text('使用你的账号和密码。', 'Use your account and password.'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (user == null) ...[
                  if (widget.onSaveServiceAddress != null) ...[
                    TextFormField(
                      controller: _serviceAddress,
                      enabled: formEnabled && !_otpShown,
                      keyboardType: TextInputType.url,
                      decoration: decoration.copyWith(
                        labelText: _text('应用服务地址', 'Application service URL'),
                        suffixIcon: IconButton(
                          tooltip: _text('保存服务地址', 'Save service URL'),
                          onPressed: formEnabled && !_otpShown
                              ? _saveAddress
                              : null,
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ?widget.signInHelp,
                  TextFormField(
                    key: const ValueKey('identity.username'),
                    controller: _username,
                    readOnly: !formEnabled || _otpShown,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    onChanged: (username) {
                      if (_prefilledAccount == null ||
                          _prefilledAccount == username) {
                        return;
                      }
                      _clearSecrets();
                      setState(() => _savePassword = false);
                    },
                    decoration: decoration.copyWith(
                      labelText: _text('用户名', 'Username'),
                      suffixIcon: _saved.isEmpty
                          ? null
                          : _savedMenu(formEnabled && !_otpShown),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('identity.password'),
                    controller: _password,
                    readOnly: !formEnabled || _otpShown,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: _otpShown
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: decoration.copyWith(
                      labelText: _text('密码', 'Password'),
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? _text('隐藏密码', 'Hide password')
                            : _text('显示密码', 'Show password'),
                        onPressed: formEnabled && !_otpShown
                            ? () =>
                                  setState(() => _showPassword = !_showPassword)
                            : null,
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) => value?.isNotEmpty == true
                        ? null
                        : _text('请输入密码', 'Enter your password'),
                    onFieldSubmitted: formEnabled && !_otpShown
                        ? (_) => _submit()
                        : null,
                  ),
                  if (widget.savedLogins != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_text('保存密码', 'Save password')),
                      value: _savePassword,
                      onChanged: formEnabled && !_otpShown
                          ? (value) =>
                                setState(() => _savePassword = value ?? false)
                          : null,
                    ),
                  if (_otpShown) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('identity.otp'),
                      controller: _otp,
                      readOnly: !formEnabled,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: decoration.copyWith(
                        labelText: _text('验证码', 'Verification code'),
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{6,8}$').hasMatch(value ?? '')
                          ? null
                          : _text('请输入有效验证码', 'Enter a valid code'),
                      onFieldSubmitted: formEnabled ? (_) => _submit() : null,
                    ),
                  ],
                ] else if (state.isVerified && widget.onRename != null)
                  TextButton.icon(
                    onPressed: busy ? null : () => _editNickname(name!),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(_text('修改昵称', 'Edit nickname')),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 12,
                  child: busy
                      ? const Center(child: LinearProgressIndicator())
                      : null,
                ),
                if (message != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          message,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_otpShown && !busy)
                  TextButton(
                    onPressed: _cancelLogin,
                    child: Text(_text('取消验证', 'Cancel verification')),
                  ),
                FilledButton.icon(
                  key: ValueKey(
                    user == null ? 'identity.submit' : 'identity.signOut',
                  ),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _canceling
                      ? null
                      : signingIn
                      ? _cancelLogin
                      : busy
                      ? null
                      : user != null || state.localCleanupRequired
                      ? widget.controller.signOut
                      : _submit,
                  icon: signingIn || _canceling
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          user != null || state.localCleanupRequired
                              ? Icons.logout_rounded
                              : Icons.login_rounded,
                        ),
                  label: Text(
                    _canceling
                        ? _text('正在取消…', 'Canceling…')
                        : signingIn
                        ? _text('取消登录', 'Cancel sign-in')
                        : user != null
                        ? _text('退出登录', 'Sign out')
                        : state.localCleanupRequired
                        ? _text('重试退出', 'Retry sign-out')
                        : _otpShown
                        ? _text('验证并登录', 'Verify and sign in')
                        : _text('登录', 'Sign in'),
                  ),
                ),
                if (offline || (state.failure?.allowsCachedIdentity ?? false))
                  TextButton(
                    onPressed: formEnabled ? widget.controller.restore : null,
                    child: Text(_text('重试连接', 'Reconnect')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _savedMenu(bool enabled) =>
      PopupMenuButton<({String account, bool forget})>(
        enabled: enabled,
        tooltip: _text('选择已保存账号', 'Choose a saved account'),
        onSelected: (item) => item.forget
            ? _forgetSaved(item.account)
            : _selectSaved(item.account),
        itemBuilder: (_) => [
          for (final account in _saved) ...[
            PopupMenuItem(
              value: (account: account, forget: false),
              child: Text(account),
            ),
            PopupMenuItem(
              value: (account: account, forget: true),
              child: Text(_text('移除 $account', 'Remove $account')),
            ),
          ],
        ],
      );

  String? _required(String? value) => value?.trim().isNotEmpty == true
      ? null
      : _text('请输入账号', 'Enter your account');

  String? _failureMessage(IdentityState state) {
    if (state.localCleanupRequired) {
      return _text('退出未完成，请重试。', 'Could not finish sign-out. Try again.');
    }
    if (state.remoteSignOutUnconfirmed) {
      return _text(
        '已退出本机，请联网确认服务端退出。',
        'Signed out locally. Reconnect to confirm server sign-out.',
      );
    }
    return switch (state.failure?.code) {
      IdentityFailureCode.invalidCredentials => _text(
        '用户名或密码不正确。',
        'Check your username and password.',
      ),
      IdentityFailureCode.otpRequired when _otpShown => _text(
        '请输入双重验证的验证码。',
        'Enter your verification code.',
      ),
      IdentityFailureCode.invalidOtp when _otpShown => _text(
        '验证码不正确。',
        'Check your verification code.',
      ),
      IdentityFailureCode.sessionRejected => _text(
        '会话已过期，请重新登录。',
        'Your session expired. Sign in again.',
      ),
      IdentityFailureCode.otpRequired ||
      IdentityFailureCode.invalidOtp ||
      IdentityFailureCode.cancelled ||
      null => null,
      _ => _text('暂时无法完成账号操作，请重试。', state.failure!.message),
    };
  }
}

final class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.current});

  final String current;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

final class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(identityText(context, '修改昵称', 'Edit nickname')),
    content: TextField(
      controller: _name,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: identityText(context, '昵称', 'Nickname'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(identityText(context, '保存', 'Save')),
      ),
    ],
  );
}
