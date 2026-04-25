# eVaka Oulu — API-muistiinpanot

Perustuu Firefox DevToolsin HAR-vientiin 2026-04-24 (session-1.har, 34 pyyntöä):
kirjautuminen, etusivun lataus, viestin luku, varauksen lisäys.

**Base URL:** `https://varhaiskasvatus.ouka.fi`

---

## 1. Autentikointi

### 1.1 Login
- **`POST /api/citizen/auth/weak-login`**
- Content-Type: `application/json`
- Headerit: `x-evaka-csrf: 1` (pakollinen), `Origin: https://varhaiskasvatus.ouka.fi`
- Body: `{"username": "<email>", "password": "<password>"}`
- Response: `200 OK`, body = `"OK"`
- Asettaa keksin `evaka.eugw.session` (32 min TTL, SameSite=Lax)

### 1.2 Status
- **`GET /api/citizen/auth/status`**
- Response:
  ```json
  {
    "loggedIn": true,
    "user": {
      "details": { "id", "firstName", "lastName", "preferredName",
                   "streetAddress", "postalCode", "postOffice",
                   "phone", "email", "weakLoginUsername" },
      "accessibleFeatures": {
        "messages": true, "composeNewMessage": true,
        "reservations": true, "childDocumentation": true
      },
      "authLevel": "WEAK"
    },
    "apiVersion": "<commit-sha>",
    "authLevel": "WEAK"
  }
  ```

### 1.3 Logout
- **`POST /api/citizen/auth/logout`** *(oletus — ei testattu HAR:issa)*

---

## 2. Lapset

- **`GET /api/citizen/children`**
- Response: lista, jokaisessa:
  - `id` (UUID), `firstName`, `lastName`, `preferredName`, `imageId`
  - `group: { id, name }`, `unit: { id, name }`
  - `upcomingPlacementType` ("DAYCARE"), `upcomingPlacementStartDate`, `upcomingPlacementIsCalendarOpen`, `upcomingPlacementUnit`
  - `permittedActions`: [`CREATE_ABSENCE`, `CREATE_HOLIDAY_ABSENCE`, `CREATE_RESERVATION`, `CREATE_ABSENCE_APPLICATION`, `READ_ABSENCE_APPLICATIONS`, `READ_SERVICE_APPLICATIONS`, `READ_SERVICE_NEEDS`, `READ_ATTENDANCE_SUMMARY`, `CREATE_CALENDAR_EVENT_TIME_RESERVATION`]
  - `serviceApplicationCreationPossible`, `absenceApplicationCreationPossible`

---

## 3. Viestit

### 3.1 Oma viestitili
- **`GET /api/citizen/messages/my-account`**
- Response: `{ "accountId": "<uuid>", "messageAttachmentsAllowed": false }`
- Tätä tarvitaan ennen lähetystä (accountId = "from"-kenttä)

### 3.2 Vastaanottajat (lähettäessä)
- **`GET /api/citizen/messages/recipients`**
- Response: `{ "messageAccounts": [{ account: {id, name, type, personId}, outOfOffice: null }, ...] }`
- `type` voi olla: `CITIZEN` (toinen huoltaja), `GROUP` (ryhmä), `PERSONAL` (yksittäinen työntekijä)

### 3.3 Saapuneet viestit (sivutettu)
- **`GET /api/citizen/messages/received?page=1`**
- Response: `{ "data": [thread, ...], pagination }`
- Thread-muoto:
  ```json
  {
    "type": "Regular",
    "id": "<thread-uuid>",
    "urgent": false,
    "children": [],
    "messageType": "BULLETIN" | "MESSAGE",
    "title": "...",
    "sensitive": false,
    "isCopy": false,
    "applicationStatus": null,
    "messages": [
      {
        "id": "<message-uuid>",
        "threadId": "<thread-uuid>",
        "sender": { "id", "name", "type": "MUNICIPAL"|"PERSONAL"|"GROUP"|"CITIZEN", "personId" },
        "recipients": [...],
        "sentAt": "ISO-8601",
        "content": "teksti",
        "readAt": "ISO-8601" | null,
        "attachments": [{ "id", "name", "contentType" }],
        "recipientNames": null
      }
    ]
  }
  ```

### 3.4 Merkitse thread luetuksi (HUOM: thread, ei yksittäinen viesti!)
- **`PUT /api/citizen/messages/threads/<thread-uuid>/read`**
- Body: tyhjä
- Response: `200`, tyhjä body

### 3.5 Lukemattomien määrä
- **`GET /api/citizen/messages/unread-count`**
- Response: pelkkä kokonaisluku, esim. `132`

### 3.6 Viestin lähetys
*TODO — ei näkynyt HAR:issa tässä sessiossa.* Espoon koodin perusteella todennäköisesti:
- **`POST /api/citizen/messages`**
- Body ainakin: `{ title, content, recipientAccountIds: [...], children: [...], urgent, sensitive }`

---

## 4. Läsnä- ja poissaolot (reservations)

### 4.1 Varausten haku
- **`GET /api/citizen/reservations?from=YYYY-MM-DD&to=YYYY-MM-DD`**
- Response-rakenne:
  ```json
  {
    "children": [{ id, firstName, lastName, imageId, upcomingPlacementType,
                   upcomingPlacementStartDate, upcomingPlacementUnitName, monthSummaries }],
    "days": [
      {
        "date": "YYYY-MM-DD",
        "holiday": false,
        "children": [
          {
            "childId": "<uuid>",
            "scheduleType": "RESERVATION_REQUIRED" | "FIXED_SCHEDULE" | "TERM_BREAK",
            "shiftCare": false,
            "absence": null | { "type": "SICKLEAVE"|"OTHER_ABSENCE"|..., "editable": bool },
            "reservations": [{ "type": "TIMES", "start": "HH:MM", "end": "HH:MM" }],
            ...
          }
        ]
      }
    ],
    "reservableRange": { "start": "YYYY-MM-DD", "end": "YYYY-MM-DD" }
  }
  ```

### 4.2 Varauksen luonti/päivitys
- **`POST /api/citizen/reservations`**
- Body = **array**, yksi entry per (lapsi, päivä):
  ```json
  [
    {
      "type": "RESERVATIONS",
      "childId": "<uuid>",
      "date": "YYYY-MM-DD",
      "reservation": { "start": "HH:MM:SS", "end": "HH:MM:SS" },
      "secondReservation": null
    }
  ]
  ```
- Samassa pyynnössä voi asettaa kerralla useille lapsille useille päiville
- Response: `200`, tyhjä body

### 4.3 Poissaolo (VARMISTETTU)
- **`POST /api/citizen/absences`**
- Body (EI array, yksi objekti):
  ```json
  {
    "childIds": ["<uuid>", "<uuid>"],
    "dateRange": { "start": "YYYY-MM-DD", "end": "YYYY-MM-DD" },
    "absenceType": "OTHER_ABSENCE" | "SICKLEAVE" | "PLANNED_ABSENCE" | "UNKNOWN_ABSENCE"
  }
  ```
- Response: `200`, tyhjä body
- **HUOM:** Selain tekee ensin `POST /api/citizen/reservations` tyyppiä `"NOTHING"` samalle päivälle tyhjentääkseen olemassa olevan varauksen, ja VASTA SITTEN kutsuu `/absences`. Eli kun merkitset poissaoloa päivälle jolla on jo varaus, tee molemmat kutsut.
  ```json
  // Ensin tyhjennä varaus:
  [{"type":"NOTHING","childId":"<uuid>","date":"YYYY-MM-DD"}]
  // Sitten poissaolo yllä olevalla rakenteella
  ```

### 4.4 Esikoulun toimintapäivät
- **`POST /api/citizen/preschool-operational-dates`**
- Body: `{ "range": { "start", "end" }, "childIds": [...] }`
- Response: `{ "<childId>": ["YYYY-MM-DD", ...] }` — päivät jolloin esikoulu on toiminnassa (tässä tyhjä koska lapset eivät esikouluikäisiä)
- Relevantti jos sovellus haluaa näyttää "ei tarvitse merkitä" -indikaattorin

---

## 5. Kalenteritapahtumat

- **`GET /api/citizen/calendar-events?start=YYYY-MM-DD&end=YYYY-MM-DD`**
- Response: array tapahtumia:
  ```json
  [{
    "id": "<uuid>",
    "title": "Eväsretki klo 9",
    "description": "...",
    "period": { "start": "YYYY-MM-DD", "end": "YYYY-MM-DD" },
    "timesByChild": {},
    "eventType": "DAYCARE_EVENT",
    "attendingChildren": {
      "<childId>": [{
        "periods": [{ start, end }],
        "type": "GROUP" | "INDIVIDUAL",
        "groupName": "...",
        "unitName": "..."
      }]
    }
  }]
  ```

---

## 6. Loma-ajat (holiday periods)

- **`GET /api/citizen/holiday-period`** — lista loma-aikoja
- **`GET /api/citizen/holiday-period/questionnaire`** — kyselyt (tässä vaiheessa tyhjä `[]`)

---

## 7. Muut etusivun badget

- `GET /api/citizen/pedagogical-documents/unread-count` → `{}` tai `{"<childId>": N}`
- `GET /api/citizen/child-documents/unread-count` → `{"<childId>": N}`
- `GET /api/citizen/child-documents/unanswered` → (samankaltainen)
- `GET /api/citizen/applications/by-guardian/notifications`
- `GET /api/citizen/daily-service-time-notifications`
- `GET /api/citizen/income/expiring`

---

## 8. Yleiset havainnot

| Asia | Arvo |
|---|---|
| CSRF-strategia | Staattinen header `x-evaka-csrf: 1` |
| Session-keksi | `evaka.eugw.session`, SameSite=Lax, 32 min |
| Device-keksi | `__Host-evaka-device-user-<hash>`, SameSite=Strict, 3 kk |
| Content-Type (kaikki) | `application/json` |
| API-prefix | `/api/citizen/...` |
| Päivämäärämuoto | `YYYY-MM-DD` |
| Aikamuoto (reservations) | `HH:MM:SS` pyynnössä, `HH:MM` vastauksessa |
| HTTP | HTTP/2 |

### Vielä varmistamatta
- Viestin lähetys: `POST /api/citizen/messages` body-rakenne
- Poissaolo: `POST /api/citizen/absences` body-rakenne
- Logout: `POST /api/citizen/auth/logout` (oletus)
- Liitteiden lataus viesteistä: todennäköisesti `/api/citizen/attachments/<id>/download`
