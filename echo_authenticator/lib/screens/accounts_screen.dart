import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../theme/echo_theme.dart';
import '../widgets/echo_wave_indicator.dart';
import 'enrollment_screen.dart';
import 'listening_screen.dart';

class AccountsScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onLockApp;
  final bool isDark;

  const AccountsScreen({
    super.key,
    required this.onToggleTheme,
    required this.onLockApp,
    required this.isDark,
  });

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<DeviceCredentials> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    final list = await StorageService.getAccounts();
    if (mounted) {
      setState(() {
        _accounts = list;
        _isLoading = false;
      });
    }
  }

  void _openAccountListening(DeviceCredentials creds) async {
    HapticFeedback.selectionClick();
    await StorageService.setActiveAccountId(creds.deviceId);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListeningScreen(
          onUnpair: () {
            Navigator.of(context).pop();
            _loadAccounts();
          },
        ),
      ),
    );
    _loadAccounts();
  }

  void _navigateToAddAccount() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnrollmentScreen(
          onEnrolled: () {
            Navigator.of(context).pop();
            _loadAccounts();
          },
        ),
      ),
    );
    _loadAccounts();
  }

  void _confirmDeleteAccount(DeviceCredentials creds) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Account?'),
        content: Text('Are you sure you want to remove ${creds.username} (${creds.deviceName}) from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              HapticFeedback.mediumImpact();
              await StorageService.removeAccount(creds.deviceId);
              _loadAccounts();
            },
            style: TextButton.styleFrom(foregroundColor: EchoTheme.bad),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Scaffold(
      backgroundColor: isDark ? EchoTheme.bgDark : EchoTheme.bgLight,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EchoWaveIndicator(height: 18),
            SizedBox(width: 8),
            Text(
              'echo',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),
        actions: [
          // Theme Toggle Button
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? const Color(0xFFFBBF24) : EchoTheme.accent,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onToggleTheme();
            },
          ),
          // Lock App Button
          IconButton(
            tooltip: 'Lock App',
            icon: Icon(
              Icons.lock_outline_rounded,
              color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.onLockApp();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _accounts.isEmpty
                ? _buildEmptyState(isDark)
                : _buildAccountsList(isDark),
      ),
      floatingActionButton: _accounts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _navigateToAddAccount,
              backgroundColor: EchoTheme.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Account',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }

  Widget _buildAccountsList(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CONNECTED ACCOUNTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
              ),
            ),
            Text(
              '${_accounts.length} Key${_accounts.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EchoTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        for (final cred in _accounts) ...[
          _buildAccountCard(cred, isDark),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 80), // Padding for FAB
      ],
    );
  }

  Widget _buildAccountCard(DeviceCredentials cred, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? EchoTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(EchoTheme.rLg),
        border: Border.all(
          color: isDark ? EchoTheme.borderDark : EchoTheme.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(EchoTheme.rLg),
          onTap: () => _openAccountListening(cred),
          onLongPress: () => _confirmDeleteAccount(cred),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Account Avatar Initial
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: EchoTheme.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: EchoTheme.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cred.username.isNotEmpty ? cred.username[0].toUpperCase() : 'E',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: EchoTheme.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Account Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cred.username,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: EchoTheme.ok,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cred.deviceName,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action Indicator (Tap to listen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_rounded,
                        size: 15,
                        color: EchoTheme.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Listen',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: EchoTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EchoTheme.accentSoft,
              ),
              child: const Center(
                child: Icon(
                  Icons.vpn_key_rounded,
                  color: EchoTheme.accent,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Accounts Linked',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pair your phone with a computer to start signing in passwordlessly.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? EchoTheme.mutedDark : EchoTheme.mutedLight,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _navigateToAddAccount,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'Pair with Computer',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: EchoTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EchoTheme.rMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
