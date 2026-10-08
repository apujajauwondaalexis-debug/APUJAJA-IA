import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

const gold = Color(0xFFFFC107);
const green = Color(0xFF2E7D32);
const bg = Color(0xFF0B0B0B);
const card = Color(0xFF1A1A1A);

void main() => runApp(const ApujajaApp());

class ApujajaApp extends StatelessWidget {
  const ApujajaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'APUJAJA IA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: gold, secondary: green),
          appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: gold),
          drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF111111)),
        ),
        home: const Splash(),
      );
}

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(color: gold, width: size / 14)),
        alignment: Alignment.center,
        child: Text('A',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: size * 0.5)),
      );
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Home()));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Logo(size: 110),
            SizedBox(height: 24),
            Text('APUJAJA IA',
                style: TextStyle(color: gold, fontSize: 30, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Votre Assistant Intelligent', style: TextStyle(color: Colors.white70)),
          ]),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const welcome =
      'Bonjour ! Je suis APUJAJA IA, votre assistant intelligent.\nComment puis-je vous aider aujourd\'hui ?';
  static const langs = {
    'Français': 'fr-FR',
    'English': 'en-US',
    'Kiswahili': 'sw-KE',
    '中文': 'zh-CN',
  };
  static const menu = [
    ['Accueil', Icons.home],
    ['Conversations', Icons.chat],
    ['Ordre du jour', Icons.event],
    ['Projets', Icons.folder],
    ['Musique', Icons.music_note],
    ['Documents', Icons.description],
    ['Contacts', Icons.contacts],
    ['Création', Icons.auto_awesome],
    ['Paramètres', Icons.settings],
  ];

  SharedPreferences? prefs;
  List<Map<String, dynamic>> convs = [];
  int cur = 0;
  int page = 0;
  String backend = '';
  String lang = 'Français';
  bool voice = true;
  bool loading = false;
  bool listening = false;
  String query = '';
  final input = TextEditingController();
  final scroll = ScrollController();
  final stt = SpeechToText();
  final tts = FlutterTts();

  String get locale => langs[lang] ?? 'fr-FR';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    prefs = p;
    backend = p.getString('backend') ?? '';
    lang = p.getString('lang') ?? 'Français';
    voice = p.getBool('voice') ?? true;
    final raw = p.getString('convs');
    if (raw != null) {
      convs = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (convs.isEmpty) newConv(save: false);
    setState(() {});
  }

  void save() => prefs?.setString('convs', jsonEncode(convs));

  String now() => DateTime.now().toIso8601String();

  void newConv({bool save = true}) {
    convs.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': 'Nouvelle conversation',
      'messages': [
        {'role': 'assistant', 'text': welcome, 'time': now()}
      ],
    });
    cur = 0;
    page = 0;
    if (save) this.save();
    setState(() {});
  }

  List get msgs => convs[cur]['messages'] as List;

  void toast(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<String> askAI() async {
    if (backend.trim().isEmpty) {
      return "Le serveur IA n'est pas encore connecté. Allez dans Paramètres et entrez l'adresse de votre backend sécurisé.";
    }
    try {
      final r = await http
          .post(Uri.parse(backend.trim()),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'language': lang,
                'messages': msgs.map((m) => {'role': m['role'], 'content': m['text']}).toList(),
              }))
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) {
        final d = jsonDecode(utf8.decode(r.bodyBytes));
        return (d['reply'] ?? 'Réponse vide.').toString();
      }
      return 'Erreur du serveur (${r.statusCode}).';
    } catch (e) {
      return 'Connexion impossible. Vérifiez votre Internet et l\'adresse du backend.';
    }
  }

  Future<void> speak(String t) async {
    await tts.setLanguage(locale);
    await tts.speak(t);
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || loading) return;
    input.clear();
    final c = convs[cur];
    if (c['title'] == 'Nouvelle conversation') {
      c['title'] = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    }
    msgs.add({'role': 'user', 'text': text, 'time': now()});
    setState(() => loading = true);
    save();
    scrollDown();
    final idx = cur;
    final reply = await askAI();
    if (idx >= convs.length) return;
    (convs[idx]['messages'] as List).add({'role': 'assistant', 'text': reply, 'time': now()});
    save();
    if (!mounted) return;
    setState(() => loading = false);
    scrollDown();
    if (voice) speak(reply);
  }

  Future<void> toggleMic() async {
    if (listening) {
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    final ok = await stt.initialize(
      onError: (e) {
        if (mounted) setState(() => listening = false);
      },
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => listening = false);
      },
    );
    if (!ok) {
      toast('Microphone indisponible ou permission refusée.');
      return;
    }
    await tts.stop();
    setState(() => listening = true);
    await stt.listen(
      localeId: locale.replaceAll('-', '_'),
      onResult: (r) {
        input.text = r.recognizedWords;
        if (r.finalResult) {
          setState(() => listening = false);
          send();
        }
      },
    );
  }

  Future<void> rename(int i) async {
    final ctl = TextEditingController(text: convs[i]['title']);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) {
      convs[i]['title'] = v.trim();
      save();
      setState(() {});
    }
  }

  void delete(int i) {
    convs.removeAt(i);
    if (convs.isEmpty) {
      newConv();
    } else {
      cur = 0;
      save();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (prefs == null || convs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: gold)));
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const Logo(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('APUJAJA IA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text('Votre Assistant Intelligent',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
            ]),
          ),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment), tooltip: 'Nouveau chat', onPressed: newConv),
          IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Profil',
              onPressed: () => toast('Profil et connexion : version 2 (Firebase).')),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(children: [
                Logo(size: 44),
                SizedBox(width: 12),
                Text('APUJAJA IA',
                    style: TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
            ),
            for (int i = 0; i < menu.length; i++)
              ListTile(
                leading: Icon(menu[i][1] as IconData, color: page == i ? gold : Colors.white70),
                title: Text(menu[i][0] as String,
                    style: TextStyle(color: page == i ? gold : Colors.white)),
                onTap: () {
                  setState(() => page = i);
                  Navigator.pop(context);
                },
              ),
          ]),
        ),
      ),
      body: SafeArea(child: body()),
    );
  }

  Widget body() {
    if (page == 0) return chat();
    if (page == 1) return conversations();
    if (page == 8) return settings();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(menu[page][1] as IconData, size: 64, color: gold),
          const SizedBox(height: 16),
          Text(menu[page][0] as String,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Ce module sera ajouté dans une prochaine version.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        ]),
      ),
    );
  }

  Widget chat() {
    final list = msgs;
    return Column(children: [
      Expanded(
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.all(12),
          itemCount: list.length + (loading ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == list.length) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('APUJAJA IA écrit...', style: TextStyle(color: Colors.white54)),
              );
            }
            return bubble(Map<String, dynamic>.from(list[i]));
          },
        ),
      ),
      if (listening)
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.graphic_eq, color: green),
            SizedBox(width: 8),
            Text('Je vous écoute...', style: TextStyle(color: green)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          IconButton.filled(
            style: IconButton.styleFrom(
                backgroundColor: listening ? Colors.red : gold,
                foregroundColor: Colors.black,
                minimumSize: const Size(52, 52)),
            icon: Icon(listening ? Icons.stop : Icons.mic),
            onPressed: toggleMic,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => send(),
              decoration: InputDecoration(
                hintText: 'Écrivez votre message...',
                filled: true,
                fillColor: card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                minimumSize: const Size(52, 52)),
            icon: const Icon(Icons.send),
            onPressed: send,
          ),
        ]),
      ),
    ]);
  }

  Widget bubble(Map<String, dynamic> m) {
    final me = m['role'] == 'user';
    final t = (m['time'] as String).length >= 16 ? (m['time'] as String).substring(11, 16) : '';
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: me ? const Color(0xFF3A2F00) : card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: me ? gold.withOpacity(0.5) : Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!me)
            const Text('APUJAJA IA',
                style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 12)),
          SelectableText(m['text'] as String, style: const TextStyle(fontSize: 15.5)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t, style: const TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: m['text'] as String));
                toast('Copié');
              },
              child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.copy, size: 17, color: Colors.white54)),
            ),
            if (!me)
              InkWell(
                onTap: () => speak(m['text'] as String),
                child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.volume_up, size: 18, color: gold)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget conversations() {
    final shown = <int>[
      for (int i = 0; i < convs.length; i++)
        if (query.isEmpty ||
            (convs[i]['title'] as String).toLowerCase().contains(query.toLowerCase()))
          i
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Rechercher une conversation',
            filled: true,
            fillColor: card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final i in shown)
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: gold),
              title: Text(convs[i]['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text((convs[i]['id'] as String).isNotEmpty
                  ? DateTime.fromMillisecondsSinceEpoch(int.parse(convs[i]['id'] as String))
                      .toString()
                      .substring(0, 16)
                  : ''),
              onTap: () => setState(() {
                cur = i;
                page = 0;
                scrollDown();
              }),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'r' ? rename(i) : delete(i),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'r', child: Text('Renommer')),
                  PopupMenuItem(value: 'd', child: Text('Supprimer')),
                ],
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget settings() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Paramètres',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: gold)),
        const SizedBox(height: 20),
        const Text('Adresse du backend IA (sécurisé)'),
        const SizedBox(height: 6),
        TextField(
          controller: TextEditingController(text: backend),
          keyboardType: TextInputType.url,
          onChanged: (v) {
            backend = v;
            prefs?.setString('backend', v);
          },
          decoration: InputDecoration(
            hintText: 'https://...',
            filled: true,
            fillColor: card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Langue de la voix'),
        DropdownButton<String>(
          value: lang,
          isExpanded: true,
          items: [for (final l in langs.keys) DropdownMenuItem(value: l, child: Text(l))],
          onChanged: (v) {
            if (v == null) return;
            setState(() => lang = v);
            prefs?.setString('lang', v);
          },
        ),
        const Text(
            'Lingala et Alur : l\'IA peut écrire dans ces langues, mais Android ne propose pas encore de voix pour elles.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: gold,
          title: const Text('Lire les réponses à voix haute'),
          value: voice,
          onChanged: (v) {
            setState(() => voice = v);
            prefs?.setBool('voice', v);
          },
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
          label: const Text('Effacer toutes les conversations'),
          onPressed: () {
            convs.clear();
            newConv();
            toast('Conversations effacées.');
          },
        ),
        const SizedBox(height: 30),
        const Center(
            child: Text('APUJAJA IA v1.0\nAlexis Patrice Jalugwaru',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white38))),
      ]);
}
