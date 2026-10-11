# Maschinenring – Einrichtung (kostenlos)

Dauer: etwa 45 Minuten. Kosten: 0 €.
Du brauchst: einen PC mit Browser, ein Gmail-Konto für den Mailversand.

**Was wohin gehört**

| Teil | Wo | Kosten |
|---|---|---|
| Datenbank, Logins, Einladungen | Supabase (Server in Frankfurt) | 0 € (Gratis-Tarif) |
| App-Dateien | GitHub Pages | 0 € |
| E-Mail-Versand | Gmail über App-Passwort | 0 € |

Inhalt des Ordners:

- `index.html` – die App
- `config.js` – hier kommen deine Supabase-Zugangsdaten rein (Schritt 4)
- `schema.sql` – die Datenbank (Schritt 2)
- `manifest.webmanifest`, `sw.js`, `icon*.png`, `icon.svg` – damit sie sich wie eine App aufs Handy legen lässt

---

## Schritt 1 – Supabase-Projekt anlegen

1. Auf **supabase.com** → *Start your project* → mit GitHub anmelden. Dafür vorher auf **github.com** ein kostenloses Konto anlegen, das brauchst du in Schritt 4 sowieso.
2. *New project*:
   - Name: `maschinenring`
   - Database Password: *Generate a password* → **irgendwo sicher speichern**
   - Region: **Central EU (Frankfurt)**
   - Plan: **Free**
3. *Create new project* → 1–2 Minuten warten.

## Schritt 2 – Datenbank einrichten

1. `schema.sql` mit einem Texteditor öffnen.
2. **Ganz unten** `deine.adresse@beispiel.de` durch **deine eigene E-Mail-Adresse** ersetzen, klein geschrieben. Wer sich als Erster mit dieser Adresse anmeldet, wird Admin.
3. In Supabase links **SQL Editor** → *New query* → den kompletten Inhalt von `schema.sql` einfügen → **Run**.
4. Unten muss stehen: *Success. No rows returned*.

## Schritt 3 – E-Mail-Versand über Gmail

Ohne diesen Schritt verschickt Supabase keine Einladungen an deine Kumpels. Der eingebaute Versand schickt nur an Supabase-Teammitglieder und höchstens 2 Mails pro Stunde.

**Tipp:** Leg dafür eine eigene Gmail-Adresse an, z. B. `maschinenring.eichstaett@gmail.com`. Dann laufen die Mails nicht über dein privates Konto.

1. Im Google-Konto unter **Sicherheit** die **2-Schritt-Verifizierung** einschalten. Ohne sie gibt es keine App-Passwörter.
2. **myaccount.google.com/apppasswords** öffnen → Name `Supabase` → *Erstellen* → das 16-stellige Passwort kopieren (ohne Leerzeichen).
3. In Supabase: **Authentication → Emails → SMTP Settings** → *Enable Custom SMTP*:
   - Sender email: deine Gmail-Adresse
   - Sender name: `Maschinenring`
   - Host: `smtp.gmail.com`
   - Port: `465`
   - Username: deine Gmail-Adresse
   - Password: das App-Passwort
   - → **Save**
4. **Authentication → Rate Limits**: *Rate limit for sending emails* auf **10** pro Stunde setzen. Das reicht für euch und bremst Missbrauch.

## Schritt 4 – App online stellen (GitHub Pages)

1. In Supabase: **Project Settings → API** (heißt je nach Version auch *Data API* / *API Keys*). Zwei Werte kopieren:
   - **Project URL**, z. B. `https://abcdefgh.supabase.co`
   - **anon public** Key, ein langer Text. **Nicht** den `service_role`-Key nehmen!
2. `config.js` öffnen und beide Werte bei `url` und `anonKey` einsetzen. Speichern.
3. Auf **github.com** → **New repository**:
   - Name: `maschinenring`
   - **Public** (nötig für kostenloses Pages; es liegt nur der App-Code dort, keine Daten)
   - → *Create repository*
4. Auf der leeren Repo-Seite *uploading an existing file* → **alle Dateien aus diesem Ordner** hineinziehen → *Commit changes*.
5. **Settings → Pages** → Source: *Deploy from a branch* → Branch: `main`, Ordner `/ (root)` → **Save**.
6. Nach 1–2 Minuten steht oben die Adresse, z. B. `https://DEINNAME.github.io/maschinenring/`. **Das ist eure App-Adresse.**

## Schritt 5 – Supabase die App-Adresse mitteilen

1. **Authentication → URL Configuration**:
   - Site URL: `https://DEINNAME.github.io/maschinenring/`
   - Redirect URLs → *Add URL*: `https://DEINNAME.github.io/maschinenring/**`
   - → Save
2. **Authentication → Sign In / Providers**:
   - *Allow new users to sign up*: **an**. Fremde können sich zwar registrieren, sehen aber nichts ohne Einladung.
   - Bei **Email**: *Confirm email* an lassen. **Email OTP Expiration** auf `86400` setzen, dann gilt der Link 24 Stunden statt 1 Stunde. → Save

## Schritt 6 – E-Mail-Texte auf Deutsch

**Authentication → Emails → Templates**. Bei zwei Vorlagen Betreff und Text ersetzen (im Feld *Message body* alles löschen und einfügen):

**„Confirm signup“** (geht an neu Eingeladene)

Betreff:
```
Einladung in den Maschinenring
```
Text:
```html
<h2>Du bist eingeladen</h2>
<p>{{ if .Data.invited_by }}{{ .Data.invited_by }} hat dich in den Maschinenring eingeladen.{{ else }}Du wurdest in den Maschinenring eingeladen.{{ end }}
Dort leiht ihr euch gegenseitig Werkzeug und Geräte aus, seht, wer was gerade hat, und meldet Schäden direkt an den Besitzer.</p>
<p><a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#22535C;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;font-weight:600">Einladung annehmen</a></p>
<p>Oder in der App diesen Code eingeben: <strong style="font-size:20px;letter-spacing:2px">{{ .Token }}</strong></p>
<p>Link und Code gelten 24 Stunden. Schon abgelaufen? Öffne <a href="{{ .SiteURL }}">die App</a> und gib deine E-Mail-Adresse ein, dann kommt ein neuer.</p>
<p style="color:#666">Du kennst niemanden aus dem Maschinenring? Dann ignorier diese E-Mail einfach.</p>
```

**„Magic Link“** (Anmeldung und erneute Einladung)

Betreff:
```
Dein Link zum Maschinenring
```
Text:
```html
<h2>Hier ist dein Link</h2>
<p>Tippe auf den Knopf, um dich im Maschinenring anzumelden. Wenn dich jemand eingeladen hat, legst du danach noch deinen Namen fest.</p>
<p><a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#22535C;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;font-weight:600">Zum Maschinenring</a></p>
<p>Oder in der App diesen Code eingeben: <strong style="font-size:20px;letter-spacing:2px">{{ .Token }}</strong></p>
<p>Link und Code gelten 24 Stunden und funktionieren einmal.</p>
<p style="color:#666">Du hast keinen Link angefordert? Dann ignorier diese E-Mail.</p>
```

## Schritt 7 – Erster Login (du als Admin)

1. App-Adresse öffnen → **die E-Mail aus Schritt 2** eingeben → *Anmelde-Link senden*.
2. Mail öffnen (evtl. im Spam-Ordner) → Link antippen → Vorname eingeben, Regeln bestätigen → **Beitreten**.
3. Unter **Gruppe** siehst du dich als *Admin*. Jetzt deine Geräte eintragen und die Kumpels einladen.

**Test:** Lade zuerst eine zweite eigene Adresse ein und prüf, ob die Mail ankommt und der Beitritt klappt.

## Schritt 8 – Aufs Handy legen

- **iPhone (Safari):** App-Adresse öffnen → Teilen-Symbol → *Zum Home-Bildschirm*
- **Android (Chrome):** App-Adresse öffnen → Menü ⋮ → *App installieren* bzw. *Zum Startbildschirm hinzufügen*

Wichtig fürs iPhone: Den Link aus der Mail öffnet iOS in Safari, nicht in der Homescreen-App. In der Homescreen-App deshalb so anmelden: E-Mail eingeben, dann den **6-stelligen Code** aus der Mail eintippen statt auf den Link zu tippen.

---

## Betrieb und Grenzen

- **Pausieren:** Supabase pausiert Gratis-Projekte nach 7 Tagen ohne Nutzung. Dann zeigt die App einen Verbindungsfehler. Lösung: im Supabase-Dashboard *Restore project* klicken, nach ein paar Minuten läuft es wieder, die Daten bleiben erhalten.
- **Sicherung:** Im Gratis-Tarif gibt es keine Backups zum Herunterladen. Ab und zu im *Table Editor* die Tabellen `tools`, `members` und `bookings` als CSV exportieren.
- **Updates:** Neue Version = geänderte Dateien auf GitHub hochladen und ersetzen (nicht `config.js` überschreiben). Auf dem Handy die App einmal schließen und neu öffnen.
- **Rechte:** Jedes Mitglied darf einladen, Geräte eintragen und Schäden melden. Zusagen, ablehnen und eigene Geräte bearbeiten darf nur der Besitzer. Mitglieder entfernen darf nur der Admin. Das prüft die Datenbank selbst, nicht nur die App.
- **Weitere Admins:** Supabase → *Table Editor* → `members` → bei der Person `role` auf `Admin` setzen.
- **Niemals** den `service_role`-Key in `config.js` oder auf GitHub legen. Der `anon`-Key darf öffentlich sein.
