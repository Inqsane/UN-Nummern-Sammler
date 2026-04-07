import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  bool settingUseSubclassHeuristics = true;
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

  static const _prefUseSubclassHeuristics = 'setting_use_subclass_heuristics';
  static const _prefSearchProvider = 'setting_search_provider';
  static const _prefConfirmDeleteAll = 'setting_confirm_delete_all';

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      settingUseSubclassHeuristics =
          prefs.getBool(_prefUseSubclassHeuristics) ?? true;

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
    await prefs.setBool(
      _prefUseSubclassHeuristics,
      settingUseSubclassHeuristics,
    );
    await prefs.setString(_prefSearchProvider, switch (settingSearchProvider) {
      SearchProvider.duckduckgo => 'duckduckgo',
      SearchProvider.wikipedia => 'wikipedia',
      SearchProvider.google => 'google',
    });
    await prefs.setBool(_prefConfirmDeleteAll, settingConfirmDeleteAll);
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

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Unterklassen automatisch ableiten"),
                      subtitle: const Text(
                        "Leitet z.B. 2 -> 2.1/2.2/2.3, 4 -> 4.1/4.2/4.3, 5 -> 5.1/5.2, 6 -> 6.1/6.2 anhand des Namens ab.",
                      ),
                      value: settingUseSubclassHeuristics,
                      onChanged: (v) => update(() {
                        settingUseSubclassHeuristics = v;
                      }),
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


  String? normalizeHazardClassHeuristic({
    required String? rawClass,
    required String? substanceName,
  }) {
    if (rawClass == null) return null;
    final k = rawClass.trim();
    if (k.isEmpty) return null;

    if (k.contains('.')) return k;

    if (!settingUseSubclassHeuristics) return k;

    final n = (substanceName ?? '').toLowerCase();

    switch (k) {
      case '2':
        // 2
        const toxicHints = <String>[
          'toxic',
          'poison',
          'inhalation hazard',
          'phosgene',
          'cyanogen',
          'arsine',
          'phosphine',
          'hydrogen cyanide',
          'chlorine',
          'hydrogen sulfide',
          'sulfur dioxide',
        ];
        for (final w in toxicHints) {
          if (n.contains(w)) return '2.3';
        }

        const flammableHints = <String>[
          'flammable',
          'acetylene',
          'hydrogen',
          'methane',
          'propane',
          'butane',
          'butylene',
          'isobutane',
          'isobutylene',
          'propene',
          'propylene',
          'ethane',
          'ethylene',
          'cyclopropane',
          'natural gas',
          'lpg',
          'petroleum gas',
        ];
        for (final w in flammableHints) {
          if (n.contains(w)) return '2.1';
        }

        return '2.2';

      case '4':
        // 4
        const wetHints = <String>[
          'water-reactive',
          'dangerous when wet',
          'with water',
          'reacts with water',
          'sodium',
          'potassium',
          'lithium',
          'calcium carbide',
          'aluminium phosphide',
          'magnesium phosphide',
          'calcium phosphide',
          'zinc phosphide',
        ];
        for (final w in wetHints) {
          if (n.contains(w)) return '4.3';
        }

        const selfHeatHints = <String>[
          'self-heating',
          'spontaneously combustible',
          'pyrophoric',
          'charcoal',
          'carbon, activated',
          'metal catalyst',
          'oily',
          'fish meal, unstabilized',
          'seed cake',
          'cotton waste, oily',
          'rags, oily',
        ];
        for (final w in selfHeatHints) {
          if (n.contains(w)) return '4.2';
        }

        // Default: 4.1
        return '4.1';

      case '5':
        // 5.1 oxidizing substances
        // 5.2 organic peroxides
        const peroxideHints = <String>[
          'peroxide',
          'organic peroxide',
          'peroxy',
          'hydroperoxide',
          'benzoyl peroxide',
          'lauroyl peroxide',
          'dicumyl peroxide',
        ];
        for (final w in peroxideHints) {
          if (n.contains(w)) return '5.2';
        }
        return '5.1';

      case '6':
        // 6.1 toxic substances
        // 6.2 infectious substances
        const infectiousHints = <String>[
          'infectious',
          'biological substance',
          'medical waste',
          'clinical waste',
          'category b',
          'affecting humans',
          'affecting animals',
        ];
        for (final w in infectiousHints) {
          if (n.contains(w)) return '6.2';
        }
        return '6.1';

      default:
        return k;
    }
  }

  String? classForSymbol({
    required String? derivedOrRawClass,
    required String? substanceName,
  }) {
    if (derivedOrRawClass == null) return null;
    final c = derivedOrRawClass.trim();
    if (c.isEmpty) return null;

    if (c.contains('.')) return c;

    if (settingUseSubclassHeuristics) {
      return normalizeHazardClassHeuristic(
        rawClass: c,
        substanceName: substanceName,
      );
    }

    if (c == '2') return '2.2';
    if (c == '4') return '4.1';
    if (c == '5') return '5.1';
    if (c == '6') return '6.1';
    return c;
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
          "https://www.google.com/search?q=${Uri.encodeComponent(q)}",
        );
      case SearchProvider.duckduckgo:
        return Uri.parse("https://duckduckgo.com/?q=${Uri.encodeComponent(q)}");
      case SearchProvider.wikipedia:
        return Uri.parse(
          "https://en.wikipedia.org/wiki/Special:Search?search=${Uri.encodeComponent(q)}",
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

                        final derivedClass = normalizeHazardClassHeuristic(
                          rawClass: klasse,
                          substanceName: name,
                        );

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
                            "${(derivedClass != null && derivedClass.isNotEmpty) ? " • Klasse: $derivedClass" : ""}",
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

    final derivedClass = normalizeHazardClassHeuristic(
      rawClass: unKlasse,
      substanceName: unName,
    );

    final symbolClass = classForSymbol(
      derivedOrRawClass: derivedClass ?? unKlasse,
      substanceName: unName,
    );

    final symbolKey = symbolClass?.replaceAll('.', '');
    final symbolAssetPath = (symbolKey == null)
        ? null
        : "assets/symbole/$symbolKey.png";

    return Scaffold(
      appBar: AppBar(
        title: const Text("UN Sammler"),
        actions: [
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
                          if (derivedClass != null && derivedClass.isNotEmpty)
                            Chip(
                              label: Text("Klasse: $derivedClass"),
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
