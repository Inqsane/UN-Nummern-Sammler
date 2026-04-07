import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MyApp());

enum AppThemeMode { system, light, dark }

enum SearchProvider { google, duckduckgo, wikipedia }

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppThemeMode appThemeMode = AppThemeMode.system;

  static const _prefThemeMode = 'setting_theme_mode';

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefThemeMode) ?? 'system';
    setState(() {
      appThemeMode = switch (v) {
        'light' => AppThemeMode.light,
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.system,
      };
    });
  }

  Future<void> _persistThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefThemeMode, switch (mode) {
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.system => 'system',
    });
  }

  void _setThemeMode(AppThemeMode mode) async {
    setState(() => appThemeMode = mode);
    await _persistThemeMode(mode);
  }

  ThemeMode _materialThemeMode() {
    return switch (appThemeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UN Sammler',
      themeMode: _materialThemeMode(),
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      home: HomeScreen(
        themeMode: appThemeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, Map<String, String>> datenbank = {}; // UN -> {name, klasse}
  Map<String, String> gespeicherteUNs = {}; // UN -> savedDate (dd.MM.yyyy)

  final TextEditingController unController = TextEditingController();
  String? unName;
  String? unKlasse;

  SearchProvider settingSearchProvider = SearchProvider.google;
  bool settingConfirmDeleteAll = true;

  static const _prefSearchProvider = 'setting_search_provider';
  static const _prefConfirmDeleteAll = 'setting_confirm_delete_all';

  static const String _appVersion = "v1.2.0";
  static const String _repoUrl = "https://github.com/Inqsane/UN-Nummern-Sammler";
  static const String _releasesUrl = "https://github.com/Inqsane/UN-Nummern-Sammler/releases";
  static const String _discordId = "Inqsane";

  String? latestReleaseTag;
  String? latestReleaseUrl;
  DateTime? latestReleasePublishedAt;
  bool latestReleaseLoading = false;
  String? latestReleaseError;

  static const double _symbolSize = 140;

  @override
  void initState() {
    super.initState();
    loadData();
    loadGespeicherteUNs();
    loadSettings();
    unController.addListener(updateUN);

    Future.microtask(fetchLatestRelease);
  }

  @override
  void dispose() {
    unController.removeListener(updateUN);
    unController.dispose();
    super.dispose();
  }

  // DB laden
  Future<void> loadData() async {
    final String jsonString = await rootBundle.loadString(
      'assets/un_with_class.json',
    );
    final Map<String, dynamic> jsonData = json.decode(jsonString);

    setState(() {
      datenbank = jsonData.map(
        (key, value) => MapEntry(key, {
          "name": (value["name"] ?? "").toString(),
          "klasse": (value["klasse"] ?? "").toString(),
        }),
      );
    });
  }

  Future<void> loadGespeicherteUNs() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final unKeys = keys.where((k) => RegExp(r'^\d{1,4}$').hasMatch(k));

    setState(() {
      gespeicherteUNs = {
        for (final key in unKeys) key: prefs.getString(key) ?? "",
      };
    });
  }

  String formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return "$d.$m.$y";
  }

  bool istGespeichert(String un) => gespeicherteUNs.containsKey(un);

  Future<void> speichern(String un) async {
    final prefs = await SharedPreferences.getInstance();
    final datum = formatDate(DateTime.now());

    await prefs.setString(un, datum);
    setState(() {
      gespeicherteUNs[un] = datum;
    });
  }

  Future<void> entfernen(String un) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(un);

    setState(() {
      gespeicherteUNs.remove(un);
    });
  }

  Future<void> toggleSpeichern(String un) async {
    if (istGespeichert(un)) {
      await entfernen(un);
    } else {
      await speichern(un);
    }
  }

  String? gespeicherterZeitpunkt(String un) {
    final v = gespeicherteUNs[un];
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final providerStr = prefs.getString(_prefSearchProvider) ?? 'google';
      settingSearchProvider = switch (providerStr) {
        'duckduckgo' => SearchProvider.duckduckgo,
        'wikipedia' => SearchProvider.wikipedia,
        _ => SearchProvider.google,
      };

      settingConfirmDeleteAll = prefs.getBool(_prefConfirmDeleteAll) ?? true;
    });
  }

  Future<void> persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSearchProvider, switch (settingSearchProvider) {
      SearchProvider.duckduckgo => 'duckduckgo',
      SearchProvider.wikipedia => 'wikipedia',
      SearchProvider.google => 'google',
    });
    await prefs.setBool(_prefConfirmDeleteAll, settingConfirmDeleteAll);
  }

  Future<void> fetchLatestRelease() async {
    if (latestReleaseLoading) return;

    setState(() {
      latestReleaseLoading = true;
      latestReleaseError = null;
    });

    try {
      final uri = Uri.parse(
        "https://api.github.com/repos/Inqsane/UN-Nummern-Sammler/releases/latest",
      );

      final res = await http.get(uri, headers: {
        "Accept": "application/vnd.github+json",
        "User-Agent": "UN-Sammler-App",
      });

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}");
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final tag = (data["tag_name"] ?? "").toString().trim();
      final htmlUrl = (data["html_url"] ?? "").toString().trim();
      final publishedAtStr = (data["published_at"] ?? "").toString().trim();

      setState(() {
        latestReleaseTag = tag.isEmpty ? null : tag;
        latestReleaseUrl = htmlUrl.isEmpty ? null : htmlUrl;
        latestReleasePublishedAt =
            publishedAtStr.isEmpty ? null : DateTime.tryParse(publishedAtStr);
      });
    } catch (e) {
      setState(() {
        latestReleaseError =
            "Konnte neuste Version nicht laden (${e.toString()})";
      });
    } finally {
      setState(() {
        latestReleaseLoading = false;
      });
    }
  }

  bool get updateVerfuegbar {
    final latest = latestReleaseTag;
    if (latest == null || latest.trim().isEmpty) return false;
    return latest.trim() != _appVersion.trim();
  }

  Uri _buildSearchUrl(String query) {
    final q = query.trim();
    switch (settingSearchProvider) {
      case SearchProvider.google:
        return Uri.parse(
          "https://www.google.com/search?q=${Uri.encodeComponent(q)}+ADR",
        );
      case SearchProvider.duckduckgo:
        return Uri.parse(
          "https://duckduckgo.com/?q=${Uri.encodeComponent(q)}+ADR",
        );
      case SearchProvider.wikipedia:
        return Uri.parse(
          "https://en.wikipedia.org/wiki/Special:Search?search=${Uri.encodeComponent(q)}+ADR",
        );
    }
  }

  Future<void> searchOnline(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final url = _buildSearchUrl(q);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void updateUN() {
    final eingabe = unController.text.trim();

    if (datenbank.containsKey(eingabe)) {
      setState(() {
        unName = datenbank[eingabe]!["name"];
        unKlasse = datenbank[eingabe]!["klasse"];
      });
    } else {
      setState(() {
        unName = null;
        unKlasse = null;
      });
    }
  }

  Future<bool> _confirmDeleteAll() async {
    if (!settingConfirmDeleteAll) return true;

    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Alle löschen?"),
            content: const Text(
              "Möchtest du wirklich alle gespeicherten UNs entfernen?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Abbrechen"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Löschen"),
              ),
            ],
          ),
        )) ??
        false;
  }

  void zeigeListe() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final items = gespeicherteUNs.keys.toList()
            ..sort((a, b) => a.compareTo(b));

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bookmark, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Gespeicherte UNs (${items.length})",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: items.isEmpty
                            ? null
                            : () async {
                                final ok = await _confirmDeleteAll();
                                if (!ok) return;

                                final prefs =
                                    await SharedPreferences.getInstance();
                                for (final k in gespeicherteUNs.keys) {
                                  await prefs.remove(k);
                                }

                                setState(() => gespeicherteUNs.clear());
                                setModalState(() {});

                                if (context.mounted) Navigator.pop(context);
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text("Alle löschen"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "Noch keine UNs gespeichert.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final un = items[index];
                          final datum = gespeicherteUNs[un] ?? "";
                          final name = datenbank[un]?["name"] ?? "-";
                          final klasse = datenbank[un]?["klasse"];

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(
                                un.length <= 3 ? un : un.substring(0, 3),
                              ),
                            ),
                            title: Text("UN $un: $name"),
                            subtitle: Text(
                              "Gespeichert am: ${datum.isEmpty ? "—" : datum}"
                              "${(klasse != null && klasse.isNotEmpty) ? " • Klasse: $klasse" : ""}",
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: () => searchOnline(name),
                                  tooltip: "Online suchen",
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: "Entfernen",
                                  onPressed: () async {
                                    await entfernen(un);
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  Map<String, dynamic> _buildBackupJson() {
    return {
      "schema": 1,
      "exported_at": DateTime.now().toUtc().toIso8601String(),
      "app_version": _appVersion,
      "saved_uns": gespeicherteUNs, 
    };
  }

  String _backupToPrettyString(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  Future<void> exportBackup({bool share = false}) async {
    final backup = _buildBackupJson();
    final text = _backupToPrettyString(backup);

    if (share) {
      await Share.share(
        text,
        subject: "UN Sammler Backup",
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Backup in Zwischenablage kopiert.")),
    );
  }

  Future<void> importBackupFromText(String raw) async {
    final txt = raw.trim();
    if (txt.isEmpty) {
      throw Exception("Leerer Text");
    }

    final decoded = json.decode(txt);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Ungültiges JSON (kein Objekt)");
    }

    final schema = decoded["schema"];
    if (schema != 1) {
      throw Exception("Unbekanntes Backup-Schema: $schema");
    }

    final saved = decoded["saved_uns"];
    if (saved is! Map) {
      throw Exception("Ungültiges Backup: saved_uns fehlt/ist falsch");
    }

    final restored = <String, String>{};
    for (final entry in saved.entries) {
      final k = entry.key.toString();
      final v = entry.value?.toString() ?? "";
      if (!RegExp(r'^\d{1,4}$').hasMatch(k)) continue;
      restored[k] = v;
    }

    final prefs = await SharedPreferences.getInstance();

    for (final k in gespeicherteUNs.keys) {
      await prefs.remove(k);
    }

    for (final e in restored.entries) {
      await prefs.setString(e.key, e.value);
    }

    setState(() {
      gespeicherteUNs = restored;
    });
  }

  Future<void> _goTo(Widget page) async {
    Navigator.pop(context); 
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    setState(() {});
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.local_shipping, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "UN Sammler",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Version $_appVersion"
                          "${updateVerfuegbar ? " • Update verfügbar" : ""}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("Info"),
              subtitle: updateVerfuegbar ? const Text("Update verfügbar") : null,
              trailing: updateVerfuegbar
                  ? Icon(
                      Icons.new_releases,
                      color: Theme.of(context).colorScheme.tertiary,
                    )
                  : null,
              onTap: () => _goTo(
                InfoPage(
                  appVersion: _appVersion,
                  repoUrl: _repoUrl,
                  releasesUrl: _releasesUrl,
                  discordId: _discordId,
                  latestReleaseLoading: latestReleaseLoading,
                  latestReleaseTag: latestReleaseTag,
                  latestReleaseUrl: latestReleaseUrl,
                  latestReleasePublishedAt: latestReleasePublishedAt,
                  latestReleaseError: latestReleaseError,
                  updateAvailable: updateVerfuegbar,
                  onRefreshLatestRelease: fetchLatestRelease,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text("Lexikon"),
              subtitle: Text("${datenbank.length} UNs"),
              onTap: () => _goTo(
                LexikonPage(
                  datenbank: datenbank,
                  gespeicherteUNs: gespeicherteUNs,
                  adrInfoByClass: adrInfoByClass,
                  onToggleSave: toggleSpeichern,
                  onSearchOnline: searchOnline,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.query_stats),
              title: const Text("Statistik"),
              onTap: () => _goTo(
                StatistikPage(
                  datenbank: datenbank,
                  gespeicherteUNs: gespeicherteUNs,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text("Einstellungen"),
              onTap: () => _goTo(
                SettingsPage(
                  themeMode: widget.themeMode,
                  onThemeModeChanged: widget.onThemeModeChanged,
                  searchProvider: settingSearchProvider,
                  confirmDeleteAll: settingConfirmDeleteAll,
                  onSearchProviderChanged: (p) async {
                    setState(() => settingSearchProvider = p);
                    await persistSettings();
                  },
                  onConfirmDeleteAllChanged: (v) async {
                    setState(() => settingConfirmDeleteAll = v);
                    await persistSettings();
                  },
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text("Export / Import"),
              onTap: () => _goTo(
                ExportImportPage(
                  onExportClipboard: () => exportBackup(share: false),
                  onExportShare: () => exportBackup(share: true),
                  onImport: (text) => importBackupFromText(text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eingabe = unController.text.trim();
    final savedAt = eingabe.isEmpty ? null : gespeicherterZeitpunkt(eingabe);

    final klasse = unKlasse;
    final symbolKey = (klasse ?? '').replaceAll('.', '');
    final symbolAssetPath =
        symbolKey.isEmpty ? null : "assets/symbole/$symbolKey.png";

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: const Text("UN Sammler"),
        actions: [
          IconButton(
            onPressed: zeigeListe,
            icon: const Icon(Icons.bookmark_outline),
            tooltip: "Gespeicherte UNs",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (updateVerfuegbar)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.new_releases),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Update verfügbar! Öffne das Menü → Info, um die neuste Version zu sehen.",
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openExternal(_releasesUrl),
                      child: const Text("Releases"),
                    ),
                  ],
                ),
              ),
            InkWell(
              onTap: zeigeListe,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Gespeicherte UNs",
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "${gespeicherteUNs.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: unController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "UN-Nummer",
                hintText: "z.B. 1203",
                prefixIcon: const Icon(Icons.numbers),
                suffixIcon: eingabe.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          unController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (unName != null)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "UN $eingabe",
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => toggleSpeichern(eingabe),
                            icon: Icon(
                              istGespeichert(eingabe)
                                  ? Icons.bookmark
                                  : Icons.bookmark_add_outlined,
                            ),
                            label: Text(
                              istGespeichert(eingabe)
                                  ? "Gespeichert"
                                  : "Speichern",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        unName ?? "",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (klasse != null && klasse.isNotEmpty)
                            Chip(
                              label: Text("Klasse: $klasse"),
                              avatar: const Icon(Icons.category_outlined),
                            ),
                          if (savedAt != null)
                            Chip(
                              label: Text("Gespeichert am: $savedAt"),
                              avatar: const Icon(Icons.event_available),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (symbolAssetPath != null)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(10),
                              child: Image.asset(
                                symbolAssetPath,
                                width: _symbolSize,
                                height: _symbolSize,
                                errorBuilder: (_, __, ___) => SizedBox(
                                  width: _symbolSize,
                                  height: _symbolSize,
                                  child: const Center(
                                    child: Text("Symbol nicht gefunden"),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => searchOnline(unName ?? ""),
                          icon: const Icon(Icons.search),
                          label: const Text("Online suchen"),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (eingabe.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  (eingabe.length < 4)
                      ? "Hinweis: UN-Nummern müssen 4-stellig sein (z.B. 0001, statt 1)."
                      : "Keine UN gefunden.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: (eingabe.length < 4)
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              "Die aktuelle Version ist NUR in Englisch verfügbar, da die UN-Datenbank auf Englisch ist. Eine deutsche Version könnte in Zukunft folgen.",
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class InfoPage extends StatelessWidget {
  const InfoPage({
    super.key,
    required this.appVersion,
    required this.repoUrl,
    required this.releasesUrl,
    required this.discordId,
    required this.latestReleaseLoading,
    required this.latestReleaseTag,
    required this.latestReleaseUrl,
    required this.latestReleasePublishedAt,
    required this.latestReleaseError,
    required this.updateAvailable,
    required this.onRefreshLatestRelease,
  });

  final String appVersion;
  final String repoUrl;
  final String releasesUrl;
  final String discordId;

  final bool latestReleaseLoading;
  final String? latestReleaseTag;
  final String? latestReleaseUrl;
  final DateTime? latestReleasePublishedAt;
  final String? latestReleaseError;

  final bool updateAvailable;
  final Future<void> Function() onRefreshLatestRelease;

  String _formatIsoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final latestText = latestReleaseLoading
        ? "Lade…"
        : (latestReleaseTag ?? (latestReleaseError ?? "—"));

    return Scaffold(
      appBar: AppBar(title: const Text("Info")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (updateAvailable)
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.new_releases),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Update verfügbar! Öffne die Releases-Seite, um die neuste Version herunterzuladen.",
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openExternal(context, releasesUrl),
                      child: const Text("Releases"),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            "UN Sammler",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text("Aktuelle Version: $appVersion"),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_alt),
            title: const Text("Neuste Version (GitHub)"),
            subtitle: Text(latestText),
            onTap: () => _openExternal(context, latestReleaseUrl ?? releasesUrl),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Aktualisieren",
              onPressed: latestReleaseLoading ? null : onRefreshLatestRelease,
            ),
          ),
          if (latestReleasePublishedAt != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 8),
              child: Text(
                "Veröffentlicht am: ${_formatIsoDate(latestReleasePublishedAt!.toLocal())}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code),
            title: const Text("GitHub Repo"),
            subtitle: Text(repoUrl),
            onTap: () => _openExternal(context, repoUrl),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.open_in_new),
            title: const Text("Releases"),
            subtitle: Text(releasesUrl),
            onTap: () => _openExternal(context, releasesUrl),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text("Discord ID"),
            subtitle: Text(discordId),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            "Hinweise",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            "• UN-/Gefahrgutdaten sind auf Englisch (Quelle/DB: Englisch).\n"
            "• Gespeicherte UNs werden lokal auf deinem Gerät gespeichert (SharedPreferences).\n"
            "• Online-Suche öffnet den Browser/externen Anbieter (Google/DuckDuckGo/Wikipedia).",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class LexikonPage extends StatefulWidget {
  const LexikonPage({
    super.key,
    required this.datenbank,
    required this.gespeicherteUNs,
    required this.adrInfoByClass,
    required this.onToggleSave,
    required this.onSearchOnline,
  });

  final Map<String, Map<String, String>> datenbank;
  final Map<String, String> gespeicherteUNs;
  final Map<String, AdrInfo> adrInfoByClass;

  final Future<void> Function(String un) onToggleSave;
  final Future<void> Function(String query) onSearchOnline;

  @override
  State<LexikonPage> createState() => _LexikonPageState();
}

class _LexikonPageState extends State<LexikonPage> {
  final TextEditingController search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<String> _filteredKeys() {
    final q = search.text.trim().toLowerCase();
    final keys = widget.datenbank.keys.toList()..sort();

    if (q.isEmpty) return keys;

    return keys.where((un) {
      final entry = widget.datenbank[un];
      final name = (entry?["name"] ?? "").toLowerCase();
      final klasse = (entry?["klasse"] ?? "").toLowerCase();
      return un.toLowerCase().contains(q) ||
          name.contains(q) ||
          klasse.contains(q);
    }).toList();
  }

  String _symbolPathForClass(String? klasse) {
    final k = (klasse ?? "").trim();
    if (k.isEmpty) return "";
    final key = k.replaceAll('.', '');
    return "assets/symbole/$key.png";
  }

  @override
  Widget build(BuildContext context) {
    final keys = _filteredKeys();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Lexikon"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Suchen",
                hintText: "UN (z.B. 1203), Name oder Klasse (z.B. 2.1)",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          search.clear();
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  "${keys.length} Ergebnisse",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (kDebugMode)
                  Text(
                    "DB: ${widget.datenbank.length}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: keys.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final un = keys[index];
                final entry = widget.datenbank[un] ?? const {};
                final name = entry["name"] ?? "-";
                final klasse = entry["klasse"];
                final saved = widget.gespeicherteUNs.containsKey(un);

                final sym = _symbolPathForClass(klasse);

                return ListTile(
                  title: Text("UN $un"),
                  subtitle: Text(
                    "$name${(klasse != null && klasse.isNotEmpty) ? " • Klasse: $klasse" : ""}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sym.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Image.asset(
                            sym,
                            width: 34,
                            height: 34,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(Icons.help_outline),
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: saved ? "Entfernen" : "Speichern",
                        icon: Icon(
                          saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                        ),
                        onPressed: () async {
                          await widget.onToggleSave(un);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LexikonDetailPage(
                        un: un,
                        name: name,
                        klasse: klasse,
                        symbolAssetPath: sym.isEmpty ? null : sym,
                        isSaved: saved,
                        savedAt: widget.gespeicherteUNs[un],
                        adrInfo: (klasse == null) ? null : widget.adrInfoByClass[klasse],
                        onToggleSave: () async {
                          await widget.onToggleSave(un);
                          if (!mounted) return;
                          setState(() {});
                        },
                        onSearchOnline: () => widget.onSearchOnline(name),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LexikonDetailPage extends StatelessWidget {
  const LexikonDetailPage({
    super.key,
    required this.un,
    required this.name,
    required this.klasse,
    required this.symbolAssetPath,
    required this.isSaved,
    required this.savedAt,
    required this.adrInfo,
    required this.onToggleSave,
    required this.onSearchOnline,
  });

  final String un;
  final String name;
  final String? klasse;
  final String? symbolAssetPath;

  final bool isSaved;
  final String? savedAt;

  final AdrInfo? adrInfo;

  final Future<void> Function() onToggleSave;
  final Future<void> Function() onSearchOnline;

  @override
  Widget build(BuildContext context) {
    final k = klasse?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text("UN $un"),
        actions: [
          IconButton(
            tooltip: "Teilen",
            icon: const Icon(Icons.share),
            onPressed: () {
              final text = "UN $un – $name"
                  "${(k != null && k.isNotEmpty) ? " – Klasse $k" : ""}";
              Share.share(text, subject: "UN $un");
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (k != null && k.isNotEmpty)
                        Chip(
                          label: Text("Klasse: $k"),
                          avatar: const Icon(Icons.category_outlined),
                        ),
                      if (savedAt != null && savedAt!.trim().isNotEmpty)
                        Chip(
                          label: Text("Gespeichert am: $savedAt"),
                          avatar: const Icon(Icons.event_available),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (symbolAssetPath != null && symbolAssetPath!.isNotEmpty)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(10),
                          child: Image.asset(
                            symbolAssetPath!,
                            width: 160,
                            height: 160,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 160,
                              height: 160,
                              child: Center(child: Text("Symbol nicht gefunden")),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: onToggleSave,
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_add_outlined,
                          ),
                          label: Text(isSaved ? "Entfernen" : "Speichern"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSearchOnline,
                          icon: const Icon(Icons.search),
                          label: const Text("Online"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "ADR / Mini-Lexikon",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (adrInfo == null)
            Text(
              "Für diese Klasse sind noch keine ADR-Infos hinterlegt.",
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      adrInfo!.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(adrInfo!.description),
                    if (adrInfo!.examples.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        "Beispiele",
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...adrInfo!.examples.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text("• $e"),
                        ),
                      ),
                    ],
                    if (adrInfo!.notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        "Hinweise",
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...adrInfo!.notes.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text("• $e"),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatistikPage extends StatelessWidget {
  const StatistikPage({
    super.key,
    required this.datenbank,
    required this.gespeicherteUNs,
  });

  final Map<String, Map<String, String>> datenbank;
  final Map<String, String> gespeicherteUNs;

  @override
  Widget build(BuildContext context) {
    final savedCount = gespeicherteUNs.length;
    final totalCount = datenbank.length;

    final classCounts = <String, int>{};
    for (final un in gespeicherteUNs.keys) {
      final klasse = datenbank[un]?["klasse"];
      if (klasse == null || klasse.trim().isEmpty) continue;
      classCounts[klasse] = (classCounts[klasse] ?? 0) + 1;
    }
    final mostCommon = classCounts.entries.isEmpty
        ? null
        : (classCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first;

    return Scaffold(
      appBar: AppBar(title: const Text("Statistik")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Übersicht",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text("Gespeicherte UNs: $savedCount"),
                  Text("UNs in Datenbank: $totalCount"),
                  const SizedBox(height: 10),
                  if (mostCommon != null)
                    Text(
                      "Häufigste Klasse (gespeichert): ${mostCommon.key} (${mostCommon.value}x)",
                    )
                  else
                    const Text("Häufigste Klasse: —"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.searchProvider,
    required this.confirmDeleteAll,
    required this.onSearchProviderChanged,
    required this.onConfirmDeleteAllChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeModeChanged;

  final SearchProvider searchProvider;
  final bool confirmDeleteAll;

  final ValueChanged<SearchProvider> onSearchProviderChanged;
  final ValueChanged<bool> onConfirmDeleteAllChanged;

  @override
  Widget build(BuildContext context) {
    String themeLabel(AppThemeMode m) => switch (m) {
          AppThemeMode.system => "System",
          AppThemeMode.light => "Hell",
          AppThemeMode.dark => "Dunkel",
        };

    String providerLabel(SearchProvider p) => switch (p) {
          SearchProvider.google => "Google",
          SearchProvider.duckduckgo => "DuckDuckGo",
          SearchProvider.wikipedia => "Wikipedia",
        };

    return Scaffold(
      appBar: AppBar(title: const Text("Einstellungen")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  title: const Text("Design"),
                  subtitle: Text(themeLabel(themeMode)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      RadioListTile<AppThemeMode>(
                        title: const Text("System"),
                        value: AppThemeMode.system,
                        groupValue: themeMode,
                        onChanged: (v) => onThemeModeChanged(v!),
                      ),
                      RadioListTile<AppThemeMode>(
                        title: const Text("Hell"),
                        value: AppThemeMode.light,
                        groupValue: themeMode,
                        onChanged: (v) => onThemeModeChanged(v!),
                      ),
                      RadioListTile<AppThemeMode>(
                        title: const Text("Dunkel"),
                        value: AppThemeMode.dark,
                        groupValue: themeMode,
                        onChanged: (v) => onThemeModeChanged(v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ListTile(
                  title: const Text("Online-Suche"),
                  subtitle: Text(providerLabel(searchProvider)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      RadioListTile<SearchProvider>(
                        title: const Text("Google"),
                        value: SearchProvider.google,
                        groupValue: searchProvider,
                        onChanged: (v) => onSearchProviderChanged(v!),
                      ),
                      RadioListTile<SearchProvider>(
                        title: const Text("DuckDuckGo"),
                        value: SearchProvider.duckduckgo,
                        groupValue: searchProvider,
                        onChanged: (v) => onSearchProviderChanged(v!),
                      ),
                      RadioListTile<SearchProvider>(
                        title: const Text("Wikipedia"),
                        value: SearchProvider.wikipedia,
                        groupValue: searchProvider,
                        onChanged: (v) => onSearchProviderChanged(v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SwitchListTile(
              title: const Text("Bestätigung beim „Alle löschen“"),
              value: confirmDeleteAll,
              onChanged: onConfirmDeleteAllChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class ExportImportPage extends StatefulWidget {
  const ExportImportPage({
    super.key,
    required this.onExportClipboard,
    required this.onExportShare,
    required this.onImport,
  });

  final Future<void> Function() onExportClipboard;
  final Future<void> Function() onExportShare;
  final Future<void> Function(String text) onImport;

  @override
  State<ExportImportPage> createState() => _ExportImportPageState();
}

class _ExportImportPageState extends State<ExportImportPage> {
  final TextEditingController importText = TextEditingController();
  bool importing = false;

  @override
  void dispose() {
    importText.dispose();
    super.dispose();
  }

  Future<void> _doImport() async {
    setState(() => importing = true);
    try {
      await widget.onImport(importText.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Import erfolgreich.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Import fehlgeschlagen: $e")),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Export / Import")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Export",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Erstellt ein Backup deiner gespeicherten UNs (inkl. Datum).",
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: widget.onExportClipboard,
                        icon: const Icon(Icons.copy),
                        label: const Text("In Zwischenablage"),
                      ),
                      FilledButton.icon(
                        onPressed: widget.onExportShare,
                        icon: const Icon(Icons.share),
                        label: const Text("Teilen"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Import",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Füge hier ein zuvor exportiertes Backup (JSON) ein.",
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: importText,
                    minLines: 6,
                    maxLines: 14,
                    decoration: InputDecoration(
                      hintText: "{\n  \"schema\": 1,\n  ...\n}",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: importing ? null : _doImport,
                    icon: importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(importing ? "Importiere…" : "Importieren"),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Hinweis: Import überschreibt deine aktuell gespeicherten UNs.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdrInfo {
  const AdrInfo({
    required this.title,
    required this.description,
    this.examples = const [],
    this.notes = const [],
  });

  final String title;
  final String description;
  final List<String> examples;
  final List<String> notes;
}

const Map<String, AdrInfo> adrInfoByClass = {
  "1": AdrInfo(
    title: "Klasse 1 – Explosive Stoffe und Gegenstände",
    description:
        "Stoffe und Gegenstände, die durch chemische Reaktion Gase bei hoher Temperatur und hohem Druck entwickeln können und dadurch Explosionen verursachen.",
    examples: ["Feuerwerkskörper", "Munition"],
    notes: ["Strenge Verpackungs- und Transportvorschriften."],
  ),
  "2.1": AdrInfo(
    title: "Klasse 2.1 – Entzündbare Gase",
    description:
        "Gase, die sich leicht entzünden können und mit Luft explosive Gemische bilden.",
    examples: ["Propan", "Butan"],
    notes: ["Zündquellen vermeiden, ausreichende Belüftung."],
  ),
  "2.2": AdrInfo(
    title: "Klasse 2.2 – Nicht entzündbare, nicht giftige Gase",
    description:
        "Gase, die weder entzündbar noch giftig sind, aber durch Druck/Ersticken gefährlich sein können.",
    examples: ["Stickstoff", "Kohlendioxid"],
    notes: ["Behälter unter Druck – vor Hitze schützen."],
  ),
  "2.3": AdrInfo(
    title: "Klasse 2.3 – Giftige Gase",
    description:
        "Gase, die beim Einatmen schwere Gesundheitsschäden verursachen können.",
    examples: ["Chlor", "Ammoniak (je nach Einstufung)"],
    notes: ["Sehr gefährlich – Schutzmaßnahmen/Notfallplanung wichtig."],
  ),
  "3": AdrInfo(
    title: "Klasse 3 – Entzündbare Flüssigkeiten",
    description:
        "Flüssigkeiten (oder flüssige Gemische), die leicht entzündlich sind und brennbare Dämpfe bilden.",
    examples: ["Benzin (UN 1203)", "Ethanol"],
    notes: ["Zündquellen vermeiden, dicht verschließen."],
  ),
  "4.1": AdrInfo(
    title: "Klasse 4.1 – Entzündbare feste Stoffe / selbstreaktive Stoffe",
    description:
        "Feste Stoffe, die leicht entzündbar sind, oder selbstreaktive Stoffe, die gefährlich reagieren können.",
    examples: ["Streichhölzer (je nach Einstufung)"],
  ),
  "4.2": AdrInfo(
    title: "Klasse 4.2 – Selbstentzündliche Stoffe",
    description:
        "Stoffe, die sich bei Kontakt mit Luft selbst entzünden können.",
    examples: ["Weißer Phosphor (Beispiel)"],
  ),
  "4.3": AdrInfo(
    title: "Klasse 4.3 – Stoffe, die mit Wasser entzündbare Gase entwickeln",
    description:
        "Stoffe, die bei Berührung mit Wasser gefährliche Mengen entzündbarer Gase freisetzen.",
    examples: ["Natrium (Beispiel)"],
  ),
  "5.1": AdrInfo(
    title: "Klasse 5.1 – Oxidierende Stoffe",
    description:
        "Stoffe, die Sauerstoff abgeben oder eine Verbrennung stark fördern können.",
    examples: ["Ammoniumnitrat (Beispiel)"],
  ),
  "5.2": AdrInfo(
    title: "Klasse 5.2 – Organische Peroxide",
    description:
        "Stoffe, die thermisch instabil sind und zu heftigen Reaktionen neigen können.",
    examples: ["MEKP (Beispiel)"],
  ),
  "6.1": AdrInfo(
    title: "Klasse 6.1 – Giftige Stoffe",
    description:
        "Stoffe, die beim Verschlucken, Einatmen oder Hautkontakt gesundheitsschädlich oder tödlich sein können.",
    examples: ["Pestizide (Beispiel)"],
  ),
  "6.2": AdrInfo(
    title: "Klasse 6.2 – Ansteckungsgefährliche Stoffe",
    description:
        "Stoffe, von denen bekannt ist oder anzunehmen ist, dass sie Krankheitserreger enthalten.",
    examples: ["Medizinische Proben (Beispiel)"],
  ),
  "7": AdrInfo(
    title: "Klasse 7 – Radioaktive Stoffe",
    description:
        "Stoffe, die ionisierende Strahlung aussenden und besondere Schutzmaßnahmen erfordern.",
    examples: ["Radioaktive Isotope (Beispiel)"],
  ),
  "8": AdrInfo(
    title: "Klasse 8 – Ätzende Stoffe",
    description:
        "Stoffe, die bei Kontakt Gewebe zerstören oder Materialien stark angreifen können.",
    examples: ["Schwefelsäure", "Natronlauge"],
  ),
  "9": AdrInfo(
    title: "Klasse 9 – Verschiedene gefährliche Stoffe und Gegenstände",
    description:
        "Stoffe/Gegenstände, die während des Transports eine Gefahr darstellen, aber keiner anderen Klasse eindeutig zugeordnet sind.",
    examples: ["Lithium-Ionen-Batterien (Beispiel)"],
  ),
};
