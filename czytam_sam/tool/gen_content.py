import json, sys, re
root = sys.argv[1]
L = json.load(open(root + '/letters.json'))
order = {l['id']: l['order'] for l in L['letters']}
GR = ['dzi', 'ch', 'cz', 'sz', 'rz', 'dz', 'dź', 'dż', 'ci', 'si', 'zi', 'ni']
gr_order = {'ch': 33, 'cz': 33, 'sz': 33, 'rz': 34, 'dz': 35, 'dź': 36, 'dż': 35,
            'si': 37, 'ci': 37, 'zi': 38, 'ni': 37, 'dzi': 38}
def tok(word):
    w = word.lower(); out = []; i = 0
    while i < len(w):
        ch = w[i]
        if not ch.isalpha(): i += 1; continue
        m = None
        for g in sorted(GR, key=len, reverse=True):
            if w.startswith(g, i): m = g; break
        if m: out.append(m); i += len(m)
        else:
            assert ch in order, (word, ch); out.append(ch); i += 1
    return out
def rank(g): return order.get(g) or gr_order[g]
def level(gs):
    r = max(rank(g) for g in gs)
    return 1 if r <= 12 else 2 if r <= 20 else 3 if r <= 32 else 4
def uniq(seq):
    s = []; [s.append(x) for x in seq if x not in s]; return s

# ---------------- SYLABY ----------------
V = ['a', 'o', 'e', 'u', 'y', 'i']
C = ['m', 'l', 't', 's', 'p', 'k', 'r', 'd', 'n', 'w', 'b', 'j', 'z', 'g', 'ł']
bad = {'ky', 'gy', 'jy', 'ji', 'ly', 'si', 'zi', 'ni', 'ci', 'ky', 'ki', 'gi', 'li', 'ti', 'di', 'ri', 'ji', 'łi', 'wi', 'bi', 'pi', 'mi'}
syl = []
for c in C:
    for v in V:
        s = c + v
        if s in bad: continue
        syl.append((s, 'CV', 'sylaba otwarta: spółgłoska + samogłoska', None))
for s in ['am', 'om', 'em', 'um', 'al', 'ol', 'el', 'ul', 'as', 'os', 'at', 'ot', 'ak', 'ok', 'ar', 'or', 'an', 'on']:
    syl.append((s, 'VC', 'sylaba zamknięta: samogłoska + spółgłoska', None))
for s, w in [('sza', None), ('szo', None), ('szu', None), ('cza', None), ('czo', None), ('czy', None), ('cha', None), ('cho', None), ('chu', None),
             ('rza', 'ża'), ('rze', 'że'), ('rzy', 'ży'), ('dzwo', None), ('dża', None), ('dżu', None)]:
    syl.append((s, 'DW', 'sylaba z dwuznakiem', w))
for s, w in [('sia', 'śa'), ('sie', 'śe'), ('sio', 'śo'), ('cia', 'ća'), ('cie', 'će'), ('cio', 'ćo'), ('zia', 'źa'), ('zie', 'źe'),
             ('nia', 'ńa'), ('nie', 'ńe'), ('nio', 'ńo'), ('dzia', 'dźa'), ('dzie', 'dźe')]:
    syl.append((s, 'ZM', 'sylaba ze zmiękczeniem: „i” tylko zmiękcza, nie wymawiamy go osobno', w))
sylout = []
for s, kind, cel, wym in syl:
    gs = tok(s)
    sylout.append({'id': 'syl_' + s, 'text': s, 'graphemes': gs, 'level': level(gs) if kind in ('CV','VC') else 4,
                   'kind': kind, 'goal': cel, 'pronunciation': wym or s, 'pronunciationNote': None if not wym else 'wymowa różni się od zapisu litera po literze'})
json.dump({'_opis': 'Sylaby. graphemes = wymagane grafemy (głoski), które dziecko musi opanować przed samodzielnym czytaniem sylaby.', 'syllables': sylout},
          open(root + '/syllables.json', 'w'), ensure_ascii=False, indent=1)

# ---------------- WYRAZY ----------------
W = """mama;tata;lala;oko;lato;kot;kos;tak;sok;sam;las;lis;mak;mus;pas;osa;ul;tama;kasa;mapa;lupa;kula;sala;sito|śito;puma;motyl;lampa;mleko;pole;lot;mata;kaktus;plama;pilot;klasa;stopa;
tort;rak;ryba;rower;rama;dom;dym;dama;noga;nos;nora;woda;wata;sowa;balon;buty;bal;bób|bup;jajo;jama;koza;zupa;zamek;gra;waga;góra|gura;łapa;łata;masło;koło;cebula;noc;córka|curka;żaba;żuk;róża|ruża;
hak;hamak;herbata;foka;fala;film;wąs|wąs (ą nosowe);ząb|zomp;mąka|monka;zęby|zemby;ręka|renka;gęś|gęś (ę nosowe);ślimak;ćma;pić;liść;koń;słoń;dłoń;dzień|dźeń;szafa;szkoła;kasza;mysz;czapka;kaczka;oczy;
ucho;mucha;chata;chleb|chlep;rzeka|żeka;morze|może;dzwon;kukurydza;dżem;dżungla;jeż|jesz;nie|ńe;kino;lody;miś;pies|pies (p zmiękczone);kura;dziadek|dźadek;ciocia|ćoća;siano|śano;zima|źima;wóz|wus;ołówek|ołuwek;łyżka|łyszka;
taca;cukier;gol;gumka;rysunek;źle;źrebak;łódź|łuć;dźwig|dźwik;okno;lalka;kubek;ser"""
REVIEW = {'gałąź': 'wymowa nosówki przed ź na końcu wyrazu wymaga weryfikacji logopedycznej'}
words = []
for item in [x.strip() for x in W.replace('\n', '').split(';') if x.strip()] + ['gałąź|?']:
    t, _, wym = item.partition('|')
    gs = tok(t)
    syll = len(re.findall(r'[aąeęioóuy]', re.sub(r'(?<=[bcćdfghjklłmnńprsśtwzźż])i(?=[aąeęoóuy])', '', t)))
    lv = level(gs) + (1 if syll >= 3 else 0)
    ent = {'id': 'w_' + t, 'text': t, 'graphemes': uniq(gs), 'level': min(lv, 5), 'syllables': syll,
           'goal': 'czytanie wyrazu %d-sylabowego' % syll, 'pronunciation': wym or t}
    if wym and wym != '?': ent['pronunciationNote'] = 'wymowa różni się od zapisu'
    if re.search(r'[bcdfghjklłmnprstwz]i[aąeęoóuy]', t) and not any(g in gs for g in ('ci','si','zi','ni','dzi')) or re.search(r'[bdfghjklłmprtw]i[aąeęoóuy]', t):
        ent['contextNote'] = '„i” przed samogłoską tylko zmiękcza poprzednią spółgłoskę (nie czytamy go osobno)'; ent['level'] = max(ent['level'], 3)
    if t in REVIEW: ent['needsReview'] = True; ent['reviewNote'] = REVIEW[t]; ent['pronunciation'] = None
    words.append(ent)
json.dump({'_opis': 'Wyrazy. needsReview=true oznacza pozycję wyłączoną z puli do czasu weryfikacji.', 'words': words},
          open(root + '/words.json', 'w'), ensure_ascii=False, indent=1)

# ---------------- ZDANIA ----------------
S = [
 ("To jest mama.", "Kto to jest?", ["mama", "tata", "kot"]),
 ("To jest kot.", "Co to jest?", ["kot", "las", "sok"]),
 ("Tata ma sok.", "Co ma tata?", ["sok", "mak", "las"]),
 ("Mama ma mak.", "Kto ma mak?", ["mama", "tata", "osa"]),
 ("Osa lata.", "Co lata?", ["osa", "kot", "ul"]),
 ("Ola ma lampę.", "Co ma Ola?", ["lampę", "mapę", "lupę"]),
 ("Lis jest w lesie.", "Gdzie jest lis?", ["w lesie", "w domu", "w wodzie"]),
 ("Mama pije mleko.", "Co pije mama?", ["mleko", "sok", "wodę"]),
 ("Kot śpi na kocu.", "Gdzie śpi kot?", ["na kocu", "na stole", "w lesie"]),
 ("Ryba pływa w wodzie.", "Gdzie pływa ryba?", ["w wodzie", "w lesie", "na łące"]),
 ("Dom jest duży.", "Jaki jest dom?", ["duży", "mały", "zimny"]),
 ("Sowa ma duże oczy.", "Kto ma duże oczy?", ["sowa", "ryba", "osa"]),
 ("Tata myje auto.", "Co myje tata?", ["auto", "kubek", "okno"]),
 ("Koza je trawę.", "Co je koza?", ["trawę", "zupę", "lody"]),
 ("Ola je lody.", "Co je Ola?", ["lody", "zupę", "mak"]),
 ("Mama gotuje zupę.", "Co gotuje mama?", ["zupę", "lody", "sok"]),
 ("Balon jest czerwony.", "Jaki jest balon?", ["czerwony", "zielony", "mały"]),
 ("Żaba skacze do wody.", "Kto skacze do wody?", ["żaba", "koza", "sowa"]),
 ("Na niebie świeci słońce.", "Co świeci na niebie?", ["słońce", "lampa", "oko"]),
 ("Zimą pada śnieg.", "Kiedy pada śnieg?", ["zimą", "latem", "rano"]),
 ("Mucha siedzi na oknie.", "Gdzie siedzi mucha?", ["na oknie", "na nosie", "w zupie"]),
 ("W szafie wisi kurtka.", "Co wisi w szafie?", ["kurtka", "lampa", "ryba"]),
 ("Kasia idzie do szkoły.", "Dokąd idzie Kasia?", ["do szkoły", "do lasu", "do domu"]),
 ("Dziadek czyta gazetę.", "Co czyta dziadek?", ["gazetę", "mapę", "książkę"]),
 ("Rano piję ciepłe mleko.", "Kiedy piję mleko?", ["rano", "wieczorem", "w nocy"]),
 ("Ciocia upiekła tort.", "Kto upiekł tort?", ["ciocia", "wujek", "babcia"]),
 ("Koń biega po łące.", "Gdzie biega koń?", ["po łące", "po domu", "po wodzie"]),
 ("Rzeka płynie przez las.", "Co płynie przez las?", ["rzeka", "ryba", "chmura"]),
 ("Jeż ma kolce.", "Kto ma kolce?", ["jeż", "kot", "żaba"]),
 ("Babcia robi dżem z truskawek.", "Z czego babcia robi dżem?", ["z truskawek", "z mleka", "z chleba"]),
 ("Dzwon dzwoni głośno.", "Jak dzwoni dzwon?", ["głośno", "cicho", "wolno"]),
 ("Kura zniosła jajo.", "Co zniosła kura?", ["jajo", "mleko", "ser"]),
 ("Tata pije kawę.", "Co pije tata?", ["kawę", "mleko", "zupę"]),
]
def gsof(text): return uniq(tok(text))
sent = []
for i, (t, q, opts) in enumerate(S, 1):
    gs = gsof(t)
    nwords = len(t.split())
    sent.append({'id': 's_%02d' % i, 'text': t, 'graphemes': gs, 'level': min(5, level(gs) + (1 if nwords > 4 else 0)),
                 'goal': 'czytanie zdania ze zrozumieniem (pytanie bez obrazka)', 'question': q, 'options': opts, 'answer': opts[0]})
json.dump({'_opis': 'Zdania z pytaniem sprawdzającym zrozumienie. answer = poprawna odpowiedź; w aplikacji kolejność opcji jest losowana.', 'sentences': sent},
          open(root + '/sentences.json', 'w'), ensure_ascii=False, indent=1)

R = [
 ("Ala i kot", "To jest Ala. Ala ma kota. Kot lubi mleko.", [("Co lubi kot?", ["mleko", "zupę", "trawę"]), ("Kto ma kota?", ["Ala", "tata", "Ola"])]),
 ("Mama i tata", "Mama ma sok. Tata ma mak. Mama i tata idą do domu.", [("Dokąd idą mama i tata?", ["do domu", "do lasu", "do szkoły"]), ("Co ma tata?", ["mak", "sok", "kota"])]),
 ("Lato", "Jest lato. Ola i Tomek są nad morzem. Woda jest ciepła.", [("Gdzie są dzieci?", ["nad morzem", "w lesie", "w szkole"]), ("Jaka jest woda?", ["ciepła", "zimna", "słodka"])]),
 ("Osa", "Osa lata nad stołem. Na stole jest dżem. Osa lubi słodki dżem.", [("Co lubi osa?", ["dżem", "zupę", "mleko"]), ("Gdzie jest dżem?", ["na stole", "w szafie", "w lesie"])]),
 ("Kot i mysz", "Kot siedzi pod szafą. Pod szafą jest mysz. Mysz szybko ucieka do nory.", [("Gdzie ucieka mysz?", ["do nory", "do szafy", "do domu"]), ("Gdzie siedzi kot?", ["pod szafą", "na oknie", "w ogrodzie"])]),
 ("Zima", "Jest zima. Pada śnieg. Dzieci lepią bałwana. Bałwan ma nos z marchewki.", [("Z czego bałwan ma nos?", ["z marchewki", "z kamienia", "z patyka"]), ("Co pada?", ["śnieg", "deszcz", "grad"])]),
 ("W sklepie", "Mama i Kasia idą do sklepu. Kupują chleb, masło i mleko. Kasia niesie koszyk.", [("Kto niesie koszyk?", ["Kasia", "mama", "tata"]), ("Co kupują?", ["chleb", "lody", "kwiaty"])]),
 ("Rower", "Tomek dostał nowy rower. Rower jest czerwony. Tomek jeździ na nim po parku. Tata uczy go hamować.", [("Jaki kolor ma rower?", ["czerwony", "zielony", "niebieski"]), ("Gdzie jeździ Tomek?", ["po parku", "po domu", "po lesie"])]),
 ("Jeż", "W ogrodzie mieszka jeż. W dzień śpi pod liśćmi. Wieczorem szuka jedzenia. Jeż ma ostre kolce.", [("Kiedy jeż szuka jedzenia?", ["wieczorem", "rano", "w południe"]), ("Gdzie jeż śpi w dzień?", ["pod liśćmi", "na drzewie", "w domu"])]),
 ("Urodziny", "Dziś są urodziny Oli. Ciocia upiekła duży tort. Na torcie jest siedem świeczek. Ola zdmuchuje świeczki i wszyscy śpiewają.", [("Ile świeczek jest na torcie?", ["siedem", "pięć", "dziesięć"]), ("Kto upiekł tort?", ["ciocia", "babcia", "mama"])]),
]
rd = []
for i, (title, t, qs) in enumerate(R, 1):
    gs = gsof(t)
    rd.append({'id': 'r_%02d' % i, 'title': title, 'text': t, 'graphemes': gs, 'level': i,
               'goal': 'czytanie krótkiego tekstu ze zrozumieniem', 'questions': [{'question': q, 'options': o, 'answer': o[0]} for q, o in qs]})
json.dump({'_opis': 'Czytanki (rosnąca trudność 1–10) z pytaniami. answer = poprawna odpowiedź.', 'readings': rd},
          open(root + '/readings.json', 'w'), ensure_ascii=False, indent=1)
print(len(sylout), len(words), len(sent), len(rd))
