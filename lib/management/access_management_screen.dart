/// Managing who may do what.
///
/// The capabilities live in the database, and this is where they are
/// changed: a role's grants, the roles a member holds, and the extra
/// capabilities granted to one person. A platform super administrator
/// may pick any organization; an organization's administrator manages
/// their own.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/app_snack.dart';
import 'package:ats_onework/shared/json_utils.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

/// The access management screen.
class AccessManagementScreen extends StatefulWidget {
  const AccessManagementScreen({super.key});

  @override
  State<AccessManagementScreen> createState() => _AccessManagementScreenState();
}

class _AccessManagementScreenState extends State<AccessManagementScreen> {
  final ExpenseStore _store = ExpenseStore.instance;

  int? _organizationId;
  List<Map<String, dynamic>> _roles = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _permissions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _members = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _organizations = <Map<String, dynamic>>[];

  /// The platform's standard capabilities and roles.
  List<Map<String, dynamic>> _catalogue = <Map<String, dynamic>>[];

  /// The platform's super administrators.
  List<Map<String, dynamic>> _superusers = <Map<String, dynamic>>[];
  bool? _superusersLoaded;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int? get _activeOrganizationId =>
      _organizationId ?? _store.currentOrganizationId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orgId = _activeOrganizationId;
      if (orgId == null) {
        setState(() {
          _loading = false;
          _error = 'You are not signed in to an organization.';
        });
        return;
      }

      // A super administrator may manage any organization, and also
      // maintains the catalogue the organizations are built from.
      if (_store.isSuperUser) {
        final orgs = await ApiClient.get('/system/organizations');
        if (orgs.statusCode == 200) {
          _organizations = ApiClient.pageItems(
            orgs,
          ).cast<Map<String, dynamic>>();
        }
        final catalogue = await ApiClient.get('/system/catalog');
        if (catalogue.statusCode == 200) {
          _catalogue = ApiClient.pageItems(
            catalogue,
          ).cast<Map<String, dynamic>>();
        }
        final superusers = await ApiClient.get('/system/users/superusers');
        if (superusers.statusCode == 200) {
          _superusers = ApiClient.pageItems(
            superusers,
          ).cast<Map<String, dynamic>>();
        }
        _superusersLoaded = true;
      }

      final roles = await ApiClient.get('/organizations/$orgId/access/roles');
      final permissions = await ApiClient.get(
        '/organizations/$orgId/access/permissions',
      );
      final members = await ApiClient.get('/users', query: {'limit': '100'});

      if (roles.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'You may not manage access in this organization.';
        });
        return;
      }
      _roles = ApiClient.pageItems(roles).cast<Map<String, dynamic>>();
      _permissions = ApiClient.pageItems(
        permissions,
      ).cast<Map<String, dynamic>>();
      _members = members.statusCode == 200
          ? ApiClient.pageItems(members).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the access model.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _store.bg;
    final card = _store.card;
    final gold = _store.accentGold;
    final frost = _store.textFrost;
    final muted = _store.textMuted;

    // A platform super administrator also maintains the catalogue the
    // organizations are built from, and who the platform administrators
    // are. An organization's administrator sees only their own.
    final isSuper = _store.isSuperUser;

    return DefaultTabController(
      length: isSuper ? 3 : 1,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: card,
          foregroundColor: frost,
          title: const Text('Access'),
          actions: [
            IconButton(
              onPressed: _load,
              icon: Icon(Icons.refresh_rounded, color: gold),
              tooltip: 'Reload',
            ),
          ],
          bottom: isSuper
              ? TabBar(
                  labelColor: gold,
                  unselectedLabelColor: muted,
                  indicatorColor: gold,
                  tabs: const [
                    Tab(text: 'Organization'),
                    Tab(text: 'Catalogue'),
                    Tab(text: 'Administrators'),
                  ],
                )
              : null,
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: gold))
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: InlineError(
                    message: _error!,
                    title: 'Could not load the access model',
                    onRetry: _load,
                  ),
                ),
              )
            : TabBarView(
                children: [
                  _organizationTab(card, gold, frost, muted),
                  if (isSuper) _catalogueTab(card, gold, frost, muted),
                  if (isSuper) _administratorsTab(card, gold, frost, muted),
                ],
              ),
      ),
    );
  }

  /// The organization's own roles, grants and people.
  Widget _organizationTab(Color card, Color gold, Color frost, Color muted) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_organizations.isNotEmpty) ...[
            const SectionHeader(title: 'Organization'),
            DropdownButtonFormField<int>(
              initialValue: _activeOrganizationId,
              isExpanded: true,
              dropdownColor: card,
              style: TextStyle(color: frost),
              items: _organizations
                  .map(
                    (org) => DropdownMenuItem<int>(
                      value: (org['organization_id'] as num?)?.toInt(),
                      child: Text(
                        org['name']?.toString() ?? '',
                        style: TextStyle(color: frost),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _organizationId = value);
                _load();
              },
            ),
            const SizedBox(height: 24),
          ],
          const SectionHeader(title: 'Roles'),
          ..._roles.map(
            (role) => _RoleTile(role: role, onTap: () => _openRole(role)),
          ),
          const SizedBox(height: 24),
          if (_members.isNotEmpty) ...[
            const SectionHeader(title: 'People'),
            ..._members.map(
              (member) =>
                  _MemberTile(member: member, onTap: () => _openMember(member)),
            ),
          ],
        ],
      ),
    );
  }

  /// The platform's standard capabilities and roles — the catalogue an
  /// organization is built from.
  Widget _catalogueTab(Color card, Color gold, Color frost, Color muted) {
    final capabilities = _catalogue
        .where((entry) => entry['kind'] == 'permission')
        .toList();
    final roles = _catalogue.where((entry) => entry['kind'] == 'role').toList();

    if (_catalogue.isEmpty) {
      return Center(
        child: Text(
          'The catalogue could not be read.',
          style: TextStyle(color: muted),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCatalogue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'The standard capabilities and roles every organization is '
            'built from. Changing one here does not change an '
            'organization that has already installed it — that is done '
            'from the roles of the organization itself.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            'Standard roles',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...roles.map(
            (role) => _CatalogueTile(
              entry: role,
              onTap: () => _openCatalogEntry(role),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Standard capabilities',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...capabilities.map(
            (capability) => _CatalogueTile(
              entry: capability,
              onTap: () => _openCatalogEntry(capability),
            ),
          ),
        ],
      ),
    );
  }

  /// The platform's super administrators.
  Widget _administratorsTab(Color card, Color gold, Color frost, Color muted) {
    if (_superusersLoaded != true) {
      return Center(
        child: Text(
          'The administrators could not be read.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSuperusers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A super administrator maintains the catalogue and may '
            'configure any organization. It is separate from an '
            "organization's own administrator, which only governs that "
            'organization.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            'Super administrators',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._superusers.map(
            (admin) => _SuperuserTile(
              admin: admin,
              onToggle: () => _toggleSuperuser(admin),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCatalogue() async {
    try {
      final response = await ApiClient.get('/system/catalog');
      if (response.statusCode == 200) {
        _catalogue = ApiClient.pageItems(response).cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // The tab shows its own error.
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadSuperusers() async {
    try {
      final response = await ApiClient.get('/system/users/superusers');
      if (response.statusCode == 200) {
        _superusers = ApiClient.pageItems(
          response,
        ).cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // The tab shows what it has.
    }
    if (mounted) {
      setState(() => _superusersLoaded = true);
    }
  }

  Future<void> _openCatalogEntry(Map<String, dynamic> entry) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _store.card,
      isScrollControlled: true,
      builder: (_) => _CatalogEntrySheet(entry: entry, onSaved: _loadCatalogue),
    );
  }

  Future<void> _toggleSuperuser(Map<String, dynamic> admin) async {
    final employeeId = (admin['employee_id'] as num?)?.toInt();
    if (employeeId == null) return;
    final isSuper = admin['is_superuser'] == true;
    final response = await ApiClient.put(
      '/system/users/$employeeId/superuser',
      {'is_superuser': !isSuper},
    );
    if (!mounted) return;
    if (response.statusCode == 200) {
      AppSnack.success(
        context,
        isSuper
            ? 'Removed the super administrator rights.'
            : 'Granted super administrator rights.',
      );
      await _loadSuperusers();
    } else {
      AppSnack.error(
        context,
        'Could not change the super administrator rights.',
      );
    }
  }

  Future<void> _openRole(Map<String, dynamic> role) async {
    final roleId = (role['role_id'] as num?)?.toInt();
    if (roleId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RoleGrantsScreen(
          role: role,
          permissions: _permissions,
          organizationId: _activeOrganizationId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMember(Map<String, dynamic> member) async {
    final employeeId = (member['employee_id'] as num?)?.toInt();
    final orgId = _activeOrganizationId;
    if (employeeId == null || orgId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _store.card,
      isScrollControlled: true,
      builder: (_) => _MemberAccessSheet(
        employeeId: employeeId,
        member: member,
        roles: _roles,
        permissions: _permissions,
        organizationId: orgId,
      ),
    );
    await _load();
  }
}

class _CatalogueTile extends StatelessWidget {
  const _CatalogueTile({required this.entry, required this.onTap});

  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final List<String> grants = stringList(entry['grants']);
    final bool isRole = entry['kind'] == 'role';
    return AppListTile(
      title: entry['name']?.toString() ?? '',
      subtitle: isRole
          ? (grants.isEmpty
                ? 'Grants nothing'
                : 'Grants ${grants.length} capabilit'
                      '${grants.length == 1 ? 'y' : 'ies'}')
          : (entry['description']?.toString() ?? ''),
      leading: Icon(
        isRole ? Icons.badge_outlined : Icons.vpn_key_outlined,
        color: palette.gold,
        size: 20,
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: onTap,
    );
  }
}

class _SuperuserTile extends StatelessWidget {
  const _SuperuserTile({required this.admin, required this.onToggle});

  final Map<String, dynamic> admin;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppListTile(
      title: admin['name']?.toString() ?? '',
      subtitle: admin['email']?.toString() ?? '',
      leading: Icon(Icons.shield_outlined, color: palette.gold, size: 20),
      trailing: Switch(
        value: admin['is_superuser'] == true,
        activeThumbColor: palette.gold,
        onChanged: (_) => onToggle(),
      ),
    );
  }
}

/// Edits one entry of the platform catalogue.
class _CatalogEntrySheet extends StatefulWidget {
  const _CatalogEntrySheet({required this.entry, required this.onSaved});

  final Map<String, dynamic> entry;
  final Future<void> Function() onSaved;

  @override
  State<_CatalogEntrySheet> createState() => _CatalogEntrySheetState();
}

class _CatalogEntrySheetState extends State<_CatalogEntrySheet> {
  final ExpenseStore _store = ExpenseStore.instance;
  late final TextEditingController _description = TextEditingController(
    text: widget.entry['description']?.toString() ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = _store.accentGold;
    final frost = _store.textFrost;
    final muted = _store.textMuted;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) => Container(
        color: _store.card,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.entry['name']?.toString() ?? '',
                style: TextStyle(
                  color: frost,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  if (widget.entry['kind'] == 'role')
                    Text(
                      'The capabilities this standard role grants are set '
                      'when a new organization is created. To change what an '
                      'existing organization grants, use the roles of that '
                      'organization.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final kind = widget.entry['kind']?.toString() ?? 'permission';
    final name = widget.entry['name']?.toString() ?? '';
    setState(() => _saving = true);
    try {
      final response = await ApiClient.put('/system/catalog/$kind/$name', {
        'description': _description.text,
      });
      if (!mounted) return;
      if (response.statusCode == 200) {
        AppSnack.success(context, 'Catalogue updated.');
        await widget.onSaved();
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        AppSnack.error(context, 'Could not update the catalogue.');
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Could not update the catalogue.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.role, required this.onTap});

  final Map<String, dynamic> role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final List<String> grants = stringList(role['permissions']);
    return AppListTile(
      title: role['name']?.toString() ?? '',
      subtitle: grants.isEmpty
          ? 'Grants nothing'
          : '${grants.length} capabilit${grants.length == 1 ? 'y' : 'ies'}',
      leading: Icon(Icons.badge_outlined, color: palette.gold, size: 20),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: onTap,
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});

  final Map<String, dynamic> member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AppListTile(
      title: member['name']?.toString() ?? '',
      subtitle: member['email']?.toString() ?? '',
      leading: Icon(
        Icons.person_outline_rounded,
        color: palette.gold,
        size: 20,
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: onTap,
    );
  }
}

/// The grants of one role: which capabilities it confers.
class _RoleGrantsScreen extends StatefulWidget {
  const _RoleGrantsScreen({
    required this.role,
    required this.permissions,
    required this.organizationId,
  });

  final Map<String, dynamic> role;
  final List<Map<String, dynamic>> permissions;
  final int? organizationId;

  @override
  State<_RoleGrantsScreen> createState() => _RoleGrantsScreenState();
}

class _RoleGrantsScreenState extends State<_RoleGrantsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;
  late Set<String> _granted;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _granted = stringList(widget.role['permissions']).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final frost = _store.textFrost;
    final muted = _store.textMuted;
    final gold = _store.accentGold;

    return Scaffold(
      backgroundColor: _store.bg,
      appBar: AppBar(
        backgroundColor: _store.card,
        foregroundColor: frost,
        title: Text(widget.role['name']?.toString() ?? 'Role'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'What the ${widget.role['name']} role may do.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                ...widget.permissions.map((permission) {
                  final name = permission['api_name']?.toString() ?? '';
                  return CheckboxListTile(
                    value: _granted.contains(name),
                    activeColor: gold,
                    checkColor: Colors.black,
                    title: Text(name, style: TextStyle(color: frost)),
                    subtitle: Text(
                      permission['description']?.toString() ?? '',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _granted.add(name);
                        } else {
                          _granted.remove(name);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final roleId = (widget.role['role_id'] as num?)?.toInt();
    final orgId = widget.organizationId;
    if (roleId == null || orgId == null) return;
    setState(() => _saving = true);
    try {
      final response = await ApiClient.put(
        '/organizations/$orgId/access/roles/$roleId/permissions',
        {'permissions': _granted.toList()},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        AppSnack.success(context, 'Role updated.');
        Navigator.of(context).pop();
      } else {
        AppSnack.error(context, 'Could not update the role.');
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Could not update the role.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// One person's access: the roles they hold and the extra capabilities
/// granted to them directly.
class _MemberAccessSheet extends StatefulWidget {
  const _MemberAccessSheet({
    required this.employeeId,
    required this.member,
    required this.roles,
    required this.permissions,
    required this.organizationId,
  });

  final int employeeId;
  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> permissions;
  final int organizationId;

  @override
  State<_MemberAccessSheet> createState() => _MemberAccessSheetState();
}

class _MemberAccessSheetState extends State<_MemberAccessSheet> {
  final ExpenseStore _store = ExpenseStore.instance;
  Set<int> _roleIds = <int>{};
  Set<String> _direct = <String>{};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiClient.get(
        '/organizations/${widget.organizationId}/access/members/${widget.employeeId}',
      );
      if (response.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final roleNames = stringList(body['roles']).toSet();
      _roleIds = widget.roles
          .where((role) => roleNames.contains(role['name']?.toString()))
          .map((role) => (role['role_id'] as num?)?.toInt() ?? 0)
          .where((id) => id != 0)
          .toSet();
      _direct = stringList(body['direct_permissions']).toSet();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frost = _store.textFrost;
    final muted = _store.textMuted;
    final gold = _store.accentGold;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        color: _store.card,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.member['name']?.toString() ?? 'Access',
                style: TextStyle(
                  color: frost,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: gold))
                  : ListView(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Text(
                          'Roles',
                          style: TextStyle(
                            color: gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ...widget.roles.map((role) {
                          final id = (role['role_id'] as num?)?.toInt() ?? 0;
                          return CheckboxListTile(
                            value: _roleIds.contains(id),
                            activeColor: gold,
                            checkColor: Colors.black,
                            title: Text(
                              role['name']?.toString() ?? '',
                              style: TextStyle(color: frost),
                            ),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _roleIds.add(id);
                                } else {
                                  _roleIds.remove(id);
                                }
                              });
                            },
                          );
                        }),
                        const SizedBox(height: 16),
                        Text(
                          'Extra capabilities',
                          style: TextStyle(
                            color: gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Granted to this person on top of their roles.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        ...widget.permissions.map((permission) {
                          final name = permission['api_name']?.toString() ?? '';
                          return CheckboxListTile(
                            value: _direct.contains(name),
                            activeColor: gold,
                            checkColor: Colors.black,
                            title: Text(name, style: TextStyle(color: frost)),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _direct.add(name);
                                } else {
                                  _direct.remove(name);
                                }
                              });
                            },
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final orgId = widget.organizationId;
      final base = '/organizations/$orgId/access/members/${widget.employeeId}';
      final roles = await ApiClient.put('$base/roles', {
        'role_ids': _roleIds.toList(),
      });
      final direct = await ApiClient.put('$base/permissions', {
        'permissions': _direct.toList(),
      });
      if (!mounted) return;
      if (roles.statusCode == 200 && direct.statusCode == 200) {
        AppSnack.success(context, 'Access updated.');
        Navigator.of(context).pop();
      } else {
        AppSnack.error(context, 'Could not update the access.');
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Could not update the access.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
