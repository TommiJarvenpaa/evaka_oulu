# Arkkitehtuuri

## Tiedostorakenne

```
lib/
├── main.dart                    # Sovelluksen entry point, teema, _AuthGate
├── api/
│   ├── evaka_client.dart        # Dio-asiakas, keksit, 401-interceptori
│   ├── endpoints.dart           # Kaikki API-URL:t yhdessä paikassa
│   ├── json_utils.dart          # asMap() / asList() — turvallinen JSON-purku
│   ├── attachments_api.dart     # Liitteiden lataus
│   ├── calendar_api.dart        # Kalenteri + keskusteluaikavaraukset
│   ├── messages_api.dart        # Viestit
│   ├── questionnaire_api.dart   # Poissaolokysely
│   ├── reservations_api.dart    # Varaukset ja poissaolot
│   └── models/
│       ├── calendar_event.dart  # CalendarEvent, DiscussionTime, AttendingChild
│       ├── message.dart         # MessageThread, Message, Attachment
│       ├── questionnaire.dart   # HolidayQuestionnaire, QuestionnaireDetails
│       └── reservations.dart    # ReservationsResponse, ReservationDay, jne.
├── auth/
│   ├── auth_service.dart        # Login, logout, session restore
│   └── secure_storage.dart      # Tunnusten tallennus (flutter_secure_storage)
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart         # Navigaatio + poissaolokysely-banneri
│   ├── messages_screen.dart
│   ├── message_thread_screen.dart
│   ├── attendance_screen.dart   # Varaukset + poissaolot
│   ├── bulk_reservation_screen.dart
│   ├── calendar_screen.dart     # Tapahtumat + discussion-varaukset
│   └── questionnaire_screen.dart
├── state/
│   └── app_state.dart           # Kaikki Riverpod-providerit
└── widgets/
    ├── child_image.dart
    └── day_card.dart
```

## State management (Riverpod)

Kaikki providerit ovat `app_state.dart`:ssa. Käytetään pääasiassa
`FutureProvider`ia, koska data haetaan API:sta asynkronisesti.

```
evakaClientProvider          Provider<EvakaClient>
  └── secureStorageProvider  Provider<SecureStorage>

authServiceProvider          Provider<AuthService>
authStatusProvider           FutureProvider<AuthStatus>

messagesApiProvider          Provider<MessagesApi>
receivedThreadsProvider      FutureProvider<ThreadsPage>
messagesUnreadCountProvider  FutureProvider<int>
myMessageAccountIdProvider   FutureProvider<String>
messagesPageProvider         StateProvider<int>   ← sivunumero

reservationsApiProvider      Provider<ReservationsApi>
reservationsProvider         FutureProvider<ReservationsResponse>

calendarApiProvider          Provider<CalendarApi>
calendarEventsProvider       FutureProvider<List<CalendarEvent>>

questionnaireApiProvider     Provider<QuestionnaireApi>
activeQuestionnairesProvider FutureProvider<List<HolidayQuestionnaire>>

attachmentsApiProvider       Provider<AttachmentsApi>
```

### Datan päivitys

Kun käyttäjä muuttaa dataa (varaus, vastaus kyselyyn, jne.), kutsutaan
`ref.invalidate(provider)`, joka pakottaa providerit hakemaan datan uudelleen.
Esimerkki:

```dart
await api.postReservations(inputs);
ref.invalidate(reservationsProvider); // näyttö päivittyy automaattisesti
```

## HTTP-asiakas (EvakaClient)

`EvakaClient` on ohut wrapper Dion ympärillä. Siinä on kaksi keskeistä
ominaisuutta:

### Keksien hallinta

`CookieManager` tallentaa ja lähettää automaattisesti session-keksit
(`evaka.eugw.session`). Keksit elävät muistissa sovelluksen ajan.

### Automaattinen re-login (401-interceptori)

Kun sessio vanhenee, palvelin palauttaa `401 Unauthorized` (plain text, ei JSON).
Interceptori `onResponse`:

1. Havaitsee `statusCode == 401`
2. Lukee tallennetut tunnukset `SecureStorage`sta
3. Tekee uuden `weakLogin`-kutsun
4. Toistaa alkuperäisen pyynnön (merkitty `_isRetry: true` estämään silmukka)
5. Jos re-login epäonnistuu → heittää `DioException`, screen näyttää virheen

## Autentikointi

```
käynnistys
  └── AuthService.restore()
        ├── lukee tunnukset SecureStoragesta
        ├── kutsuu weakLogin(email, password)
        │     └── onnistuu → AuthStatus.authenticated → HomeScreen
        └── epäonnistuu → AuthStatus.unauthenticated → LoginScreen
```

Käyttäjän kirjautuessa `AuthService.login()` tallentaa tunnukset
`SecureStorage`en, jotta re-login ja käynnistysrestore toimivat.

## Näyttörakenne

```
_AuthGate (main.dart)
├── LoginScreen          (unauthenticated)
└── HomeScreen           (authenticated)
    ├── _QuestionnaireBanner  (aktiivinen kysely → QuestionnaireScreen)
    ├── NavigationBar
    │   ├── MessagesScreen
    │   │   └── MessageThreadScreen
    │   ├── AttendanceScreen
    │   │   └── BulkReservationScreen
    │   └── CalendarScreen
    │       └── (Discussion slots expandable inline)
    └── QuestionnaireScreen (push)
```

## Uuden ominaisuuden lisääminen

Tyypillinen flow uudelle API-ominaisuudelle:

1. **Endpoint** — lisää `endpoints.dart`:iin
2. **Malli** — luo `lib/api/models/` alle `.dart`-tiedosto
3. **API-luokka** — luo `lib/api/xxx_api.dart`, injektoi `EvakaClient`
4. **Provider** — lisää `app_state.dart`:iin `Provider` + `FutureProvider`
5. **Näyttö** — luo tai päivitä screen, käytä `ref.watch(provider)`

## Merkittävät rajoitteet ja erityistapaukset

### validateStatus
`EvakaClient` hyväksyy kaikki HTTP-vastaukset alle 500 (`status < 500`)
ilman poikkeusta. Tämä tarkoittaa, että 400-vastauksista ei automaattisesti
tule poikkeusta — tarkista tarvittaessa `resp.statusCode` erikseen.

### JSON-purku
Dio yrittää purkaa `ResponseType.json`-vastauksia automaattisesti, mutta
`Content-Type: text/plain` -vastauksille se ei onnistu. `asMap()` ja `asList()`
(`json_utils.dart`) käsittelevät molemmat tapaukset.

### Aikamuodot
- Päivämäärät API:ssa: `YYYY-MM-DD`
- Kellonajat varauksissa: `HH:MM:SS` pyynnössä, `HH:MM` vastauksessa
- `DiscussionTime.startHHmm` / `endHHmm` katkaisevat sekunnit automaattisesti
