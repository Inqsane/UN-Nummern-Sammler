import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
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
  // Daten
  Map<String, Map<String, String>> datenbank = {};
  Map<String, String> gespeicherteUNs = {};

  final TextEditingController unController = TextEditingController();

  String? unName;
  String? unKlasse;

  SearchProvider settingSearchProvider = SearchProvider.google;
  bool settingConfirmDeleteAll = true;

  static const double _symbolSize = 140;

  @override
  void initState() {
    super.initState();
    loadData();
    loadGespeicherteUNs();
    loadSettings();
    unController.addListener(updateUN);
  }

  @override
  void dispose() {
    unController.removeListener(updateUN);
    unController.dispose();
    super.dispose();
  }

  // Daten laden NICHTS VERÄNDERN BITTE - Danke A.

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

  // settings block

  static const _prefSearchProvider = 'setting_search_provider';
  static const _prefConfirmDeleteAll = 'setting_confirm_delete_all';

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

  // ====== About / Info ======

  static const String _appVersion = "v1.0.0";
  static const String _repoUrl = "https://github.com/Inqsane/UN-Nummern-Sammler";
  static const String _releasesUrl =
      "https://github.com/Inqsane/UN-Nummern-Sammler/releases";
  static const String _discordId = "Inqsane";

  String? latestReleaseTag;
  String? latestReleaseUrl;
  DateTime? latestReleasePublishedAt;
  bool latestReleaseLoading = false;
  String? latestReleaseError;

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> fetchLatestRelease() async {
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
        latestReleasePublishedAt = publishedAtStr.isEmpty
            ? null
            : DateTime.tryParse(publishedAtStr);
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

  String _formatIsoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  void showInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> refresh() async {
              setDialogState(() {
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
                final publishedAtStr =
                    (data["published_at"] ?? "").toString().trim();

                setDialogState(() {
                  latestReleaseTag = tag.isEmpty ? null : tag;
                  latestReleaseUrl = htmlUrl.isEmpty ? null : htmlUrl;
                  latestReleasePublishedAt = publishedAtStr.isEmpty
                      ? null
                      : DateTime.tryParse(publishedAtStr);
                });
              } catch (e) {
                setDialogState(() {
                  latestReleaseError =
                      "Konnte neuste Version nicht laden (${e.toString()})";
                });
              } finally {
                setDialogState(() {
                  latestReleaseLoading = false;
                });
              }
            }

            // Beim ersten Öffnen automatisch laden (nur wenn noch nichts da ist)
            if (!latestReleaseLoading &&
                latestReleaseTag == null &&
                latestReleaseError == null) {
              Future.microtask(refresh);
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  const Text("Info"),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "UN Sammler",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),

                    Text("Version: $_appVersion"),
                    const SizedBox(height: 12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.system_update_alt),
                      title: const Text("Neuste Version"),
                      subtitle: Text(
                        latestReleaseLoading
                            ? "Lade…"
                            : (latestReleaseTag ??
                                (latestReleaseError ?? "—")),
                      ),
                      onTap: () => _openExternal(
                        latestReleaseUrl ?? _releasesUrl,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: "Aktualisieren",
                        onPressed: latestReleaseLoading ? null : refresh,
                      ),
                    ),
                    if (latestReleasePublishedAt != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 56, bottom: 8),
                        child: Text(
                          "Veröffentlicht am: ${_formatIsoDate(latestReleasePublishedAt!.toLocal())}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],

                    const Divider(height: 20),

                    const Text("Links"),
                    const SizedBox(height: 6),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.code),
                      title: const Text("GitHub Repo"),
                      subtitle: Text(_repoUrl),
                      onTap: () => _openExternal(_repoUrl),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.open_in_new),
                      title: const Text("Releases"),
                      subtitle: Text(_releasesUrl),
                      onTap: () => _openExternal(_releasesUrl),
                    ),

                    const Divider(height: 20),

                    const Text("Kontakt"),
                    const SizedBox(height: 6),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: const Text("Discord ID"),
                      subtitle: Text(_discordId),
                    ),

                    const Divider(height: 20),

                    const Text("Hinweise"),
                    const SizedBox(height: 6),
                    Text(
                      "• UN-/Gefahrgutdaten sind auf Englisch (Quelle/DB: Englisch).\n"
                      "• Gespeicherte UNs werden lokal auf deinem Gerät gespeichert (SharedPreferences).\n"
                      "• Online-Suche öffnet den Browser/externen Anbieter (Google/DuckDuckGo/Wikipedia).",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Schließen"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              Future<void> update(VoidCallback fn) async {
                fn();
                setModalState(() {});
                setState(() {});
                await persistSettings();
              }

              String themeLabel(AppThemeMode m) => switch (m) {
                AppThemeMode.system => "System",
                AppThemeMode.light => "Hell",
                AppThemeMode.dark => "Dunkel",
              };

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Einstellungen",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Design"),
                      subtitle: Text(themeLabel(widget.themeMode)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          builder: (_) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RadioListTile<AppThemeMode>(
                                    title: const Text("System"),
                                    value: AppThemeMode.system,
                                    groupValue: widget.themeMode,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      widget.onThemeModeChanged(v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  RadioListTile<AppThemeMode>(
                                    title: const Text("Hell"),
                                    value: AppThemeMode.light,
                                    groupValue: widget.themeMode,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      widget.onThemeModeChanged(v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  RadioListTile<AppThemeMode>(
                                    title: const Text("Dunkel"),
                                    value: AppThemeMode.dark,
                                    groupValue: widget.themeMode,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      widget.onThemeModeChanged(v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),

                    const Divider(),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Online-Suche"),
                      subtitle: Text(switch (settingSearchProvider) {
                        SearchProvider.google => "Google",
                        SearchProvider.duckduckgo => "DuckDuckGo",
                        SearchProvider.wikipedia => "Wikipedia",
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          builder: (_) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RadioListTile<SearchProvider>(
                                    title: const Text("Google"),
                                    value: SearchProvider.google,
                                    groupValue: settingSearchProvider,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      update(() => settingSearchProvider = v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  RadioListTile<SearchProvider>(
                                    title: const Text("DuckDuckGo"),
                                    value: SearchProvider.duckduckgo,
                                    groupValue: settingSearchProvider,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      update(() => settingSearchProvider = v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  RadioListTile<SearchProvider>(
                                    title: const Text("Wikipedia"),
                                    value: SearchProvider.wikipedia,
                                    groupValue: settingSearchProvider,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      update(() => settingSearchProvider = v);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),

                    const Divider(),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Bestätigung beim „Alle löschen“"),
                      value: settingConfirmDeleteAll,
                      onChanged: (v) => update(() {
                        settingConfirmDeleteAll = v;
                      }),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // lookup

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

  String formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return "$d.$m.$y";
  }

  String? gespeicherterZeitpunkt(String un) {
    final v = gespeicherteUNs[un];
    if (v == null || v.trim().isEmpty) return null;
    return v;
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
    final items = gespeicherteUNs.keys.toList()..sort((a, b) => a.compareTo(b));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
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
                                onPressed: () => entfernen(un),
                                tooltip: "Entfernen",
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
      appBar: AppBar(
        title: const Text("UN Sammler"),
        actions: [
          IconButton(
            onPressed: showInfoDialog,
            icon: const Icon(Icons.info_outline),
            tooltip: "Info",
          ),
          IconButton(
            onPressed: showSettingsSheet,
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Einstellungen",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
