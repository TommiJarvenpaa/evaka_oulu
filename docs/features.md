# Ominaisuudet — toteutus ja laajennusohjeet

## 1. Kirjautuminen

**Tiedostot:** `auth_service.dart`, `secure_storage.dart`, `screens/login_screen.dart`

Sovellus käyttää eVakan "weak login" -mekanismia (sähköposti + salasana), joka
ei vaadi vahvaa tunnistautumista. Tämä on sama mekanismi kuin selaimen kirjautuminen.

**Käynnistysvaihe:**
1. `AuthService.restore()` lukee tunnukset `SecureStorage`sta
2. Jos löytyy, kutsuu `weakLogin` — onnistuminen asettaa session-keksit
3. `_AuthGate` (`main.dart`) näyttää `HomeScreen`in tai `LoginScreen`in

**Tietoturva:** Tunnukset tallennetaan Android Keystore -salauksella
(`encryptedSharedPreferences: true`). Palvelimen sessio-keksi elää vain muistissa
(ei levyllä).

---

## 2. Viestit

**Tiedostot:** `messages_api.dart`, `screens/messages_screen.dart`,
`screens/message_thread_screen.dart`, `models/message.dart`

**Sivutus:** `messagesPageProvider` (StateProvider) pitää nykyisen sivunumeron.
Sivunumeron muutos invalidoi `receivedThreadsProvider`:in automaattisesti.

**Viestin merkitseminen luetuksi:** Tapahtuu heti kun `MessageThreadScreen`
avataan (`initState` → `_markRead`). Epäonnistuminen on hiljainen — yritetään
uudelleen seuraavalla avauksella.

**Vastaaminen:**
- `_ReplyComposer` rakentaa vastaanottajalistan (`_resolveRecipients`):
  alkuperäisen viestin lähettäjä + muut vastaanottajat paitsi oma tili
- Lähetyksen jälkeen navigoidaan takaisin listaukseen ja invalidoidaan providerit

**Ei vielä toteutettu:**
- Uuden viestin aloittaminen (tarvitaan `GET /api/citizen/messages/recipients`)
- Viestin arkistointi (`PUT .../archive`)

---

## 3. Läsnäolo ja varaukset

**Tiedostot:** `reservations_api.dart`, `screens/attendance_screen.dart`,
`screens/bulk_reservation_screen.dart`, `models/reservations.dart`

**Yksittäinen päivä (`_EditSheet`):**
- Käyttäjä valitsee jokaiselle lapselle tilan: läsnä (kellonajat), poissa, sairas, tyhjä
- `DaySpec` + `DayKind` (`widgets/day_card.dart`) mallintavat käyttäjän valinnan
- Tallennus: ensin `postReservations`, sitten `postAbsence` — poissaolo vaatii
  aina ensin `NOTHING`-varauksen olemassa olevan varauksen päälle

**Massailmoitus (`BulkReservationScreen`):**
- Mahdollistaa saman merkinnän tekemisen usealle päivälle kerralla
- Aikavälin ja lasten valinta, sitten sama API-logiikka kuin yksittäisessä

**Päivän tilan näyttö:**
- `scheduleType == "FIXED_SCHEDULE"` → kiinteä aikataulu, ei muokattavissa
- `scheduleType == "TERM_BREAK"` → loma-aika
- `reservationsClosed == true` → varausaika suljettu (voi silti merkitä poissaoloja)
- `reservableRange` → palvelin kertoo mihin asti varauksia voi tehdä

---

## 4. Kalenteri

**Tiedostot:** `calendar_api.dart`, `screens/calendar_screen.dart`,
`models/calendar_event.dart`

Tapahtumia on kahta tyyppiä:

### DAYCARE_EVENT
Tavallinen päiväkotitapahtuma (retki, juhlat jne.). Näytetään `_EventCard`-widgetissä.
`attendingChildren` kertoo ketkä lapset osallistuvat ja missä ryhmässä.

### DISCUSSION_SURVEY
Keskusteluaikavarausmahdollisuus. Näytetään `_DiscussionCard`-widgetissä.

`timesByChild` sisältää kaikki aikaslotit per lapsi:
- `childId == null` → vapaa aika → "Varaa"-painike
- `childId == eligibleChildId` → lapsi on varannut → "Peruuta"-painike
- `childId != null && != eligibleChildId` → varattuna toiselle → ei painiketta

Lapsi voi varata vain yhden ajan per tapahtuma. Tarkistus:
```dart
final alreadyBooked = slots.any((s) => s.childId == eligibleChildId);
```

---

## 5. Poissaolokysely

**Tiedostot:** `questionnaire_api.dart`, `screens/questionnaire_screen.dart`,
`models/questionnaire.dart`

Loma-aikoina (kesä, hiihtoloma jne.) eVaka pyytää ilmoittamaan lasten poissaolot
etukäteen. Tämä vaikuttaa asiakasmaksuihin (vapaat poissaolot).

**Kyselytyypit:**
- `OPEN_RANGES` — käyttäjä valitsee vapaat päivämäärävälit (toteutettu)
- `FIXED_PERIOD` — käyttäjä valitsee yhden jakson listasta (API tiedossa, ei UI:ta)

**Banneri (`HomeScreen`):**
- Punainen = kysely auki, ei vastattu
- Vihreä = kysely auki, vastattu (voi muokata)
- Ei näytetä = kysely ei ole auki (`questionnaire.active` -aikavälin ulkopuolella)

**`previousAnswers`:** Palvelin palauttaa aiemmin tallennetut vastaukset.
`QuestionnaireScreen.initState()` esitäyttää lomakkeen niillä.

---

## 6. Session-hallinta (re-login)

**Tiedosto:** `api/evaka_client.dart`

Sessio vanhenee ~32 minuutissa. `EvakaClient`:n `onResponse`-interceptori
hoitaa uusinnan läpinäkyvästi:

```
API-pyyntö → 401 vastaus
  ↓
interceptori lukee tunnukset SecureStoragesta
  ↓
weakLogin (merkitty _isRetry: true, ei triggeroi uudelleen)
  ↓
alkuperäinen pyyntö uudelleen (merkitty _isRetry: true)
  ↓
onnistui → käyttäjä ei huomaa mitään
epäonnistui → DioException → screen näyttää "Yritä uudelleen"
```

---

## Tunnetut puutteet ja jatkokehitysideat

| Ominaisuus | Prioriteetti | Huomio |
|---|---|---|
| Uuden viestin kirjoittaminen | Korkea | API tunnettu, tarvitaan vastaanottajavalinta |
| Etusivun notifikaatiobadget | Matala | 6 endpointia valmiina, vain UI puuttuu |
| `FIXED_PERIOD`-kysely | Matala | API tunnettu, UI tekemättä |
| Push-notifikaatiot | Matala | Vaatisi erillisen palvelun |
| Offline-tuki | Matala | Tällä hetkellä ei välimuistia |
| Hakemukset ja palvelutarpeet | Matala | Endpointit tunnettu, laaja kokonaisuus |

---

## Lisäresurssit

- **eVaka-lähdekoodi (Espoo):** https://github.com/espoon-voltti/evaka
  — Citizen-frontendin API-kutsut: `frontend/src/citizen-frontend/`
  — Kotlin-backend reitit: `service/src/main/kotlin/.../citizen/`
- **API-tyypit (TypeScript):** `frontend/src/lib-common/generated/api-types/`
  — Nämä ovat virallisia malleja jotka vastaavat JSON-rakenteita
