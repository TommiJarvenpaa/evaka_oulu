# API-dokumentaatio

**Base URL:** `https://varhaiskasvatus.ouka.fi`  
**API-prefix:** `/api/citizen/`  
**Protokolla:** HTTP/2  

Kaikki reitit löytyvät koodista: `lib/api/endpoints.dart`

## Yleiset headerit (kaikki pyynnöt)

```
x-evaka-csrf: 1
Origin: https://varhaiskasvatus.ouka.fi
User-Agent: evaka-oulu-client/0.1 (unofficial; personal use)
Accept: application/json, text/plain, */*
```

Sisältöä lähettävissä pyynnöissä myös:
```
Content-Type: application/json
```

## Session

Palvelin asettaa kirjautuessa kaksi keksiä:

| Keksi | TTL | Tarkoitus |
|---|---|---|
| `evaka.eugw.session` | ~32 min | Session-tunniste |
| `__Host-evaka-device-user-<hash>` | ~3 kk | Laitteen tunnistus |

Session vanhenee melko nopeasti. Sovellus uusii sen automaattisesti 401-interceptorissa
(ks. `evaka_client.dart`).

---

## 1. Autentikointi

### POST `/api/citizen/auth/weak-login`
Kirjautuminen sähköpostilla ja salasanalla.

```json
// Pyyntö
{ "username": "email@example.com", "password": "salasana" }

// Vastaus 200
"OK"
```

### GET `/api/citizen/auth/status`
Tarkistaa onko sessio voimassa.

```json
{
  "loggedIn": true,
  "user": {
    "details": {
      "id": "<uuid>",
      "firstName": "Etunimi",
      "lastName": "Sukunimi",
      "preferredName": "...",
      "email": "...",
      "weakLoginUsername": "email@example.com"
    },
    "accessibleFeatures": {
      "messages": true,
      "composeNewMessage": true,
      "reservations": true,
      "childDocumentation": true
    },
    "authLevel": "WEAK"
  }
}
```

### POST `/api/citizen/auth/logout`
Tyhjentää session palvelimella. Vastaus `200`, tyhjä body.

---

## 2. Lapset

### GET `/api/citizen/children`

```json
[
  {
    "id": "<uuid>",
    "firstName": "Lapsi",
    "lastName": "Sukunimi",
    "preferredName": "Kutsumanimi",
    "imageId": "<uuid> | null",
    "upcomingPlacementType": "DAYCARE",
    "upcomingPlacementUnitName": "Pikkutuulen päiväkoti",
    "permittedActions": [
      "CREATE_ABSENCE",
      "CREATE_RESERVATION",
      "CREATE_CALENDAR_EVENT_TIME_RESERVATION"
    ]
  }
]
```

### GET `/api/citizen/child-images/<imageId>`
Palauttaa kuvan binäärisisältönä. Dio palauttaa `Uint8List`.

---

## 3. Viestit

### GET `/api/citizen/messages/my-account`
```json
{ "accountId": "<uuid>", "messageAttachmentsAllowed": false }
```

### GET `/api/citizen/messages/received?page=1`
```json
{
  "data": [
    {
      "id": "<uuid>",
      "title": "Otsikko",
      "urgent": false,
      "messageType": "MESSAGE" | "BULLETIN",
      "messages": [
        {
          "id": "<uuid>",
          "sender": {
            "id": "<uuid>",
            "name": "Lähettäjä",
            "type": "MUNICIPAL" | "GROUP" | "PERSONAL" | "CITIZEN",
            "personId": "<uuid>"
          },
          "recipients": [{ "id", "name", "type" }],
          "sentAt": "2026-04-01T10:00:00Z",
          "content": "Viestin sisältö",
          "readAt": "2026-04-01T11:00:00Z" ,
          "attachments": [{ "id": "<uuid>", "name": "liite.pdf", "contentType": "application/pdf" }]
        }
      ]
    }
  ],
  "total": 42,
  "pages": 5,
  "page": 1
}
```

### GET `/api/citizen/messages/unread-count`
Palauttaa pelkän kokonaisluvun, esim. `3`. Ei JSON-objektia.

### PUT `/api/citizen/messages/threads/<threadId>/read`
Merkitsee viestiketjun luetuksi. Tyhjä body, vastaus `200`.

### POST `/api/citizen/messages/reply-to/<threadId>`
```json
{
  "content": "Vastauksen teksti",
  "recipientAccountIds": ["<accountId>", "<accountId>"]
}
```
Vastaanottajat määritetään käsin: yleensä alkuperäisen viestin lähettäjä
+ muut vastaanottajat paitsi oma tili.

### GET `/api/citizen/attachments/<id>/download/<filename>`
Lataa liitteen. Dio tallentaa tiedoston `path_provider`in temp-kansioon.

---

## 4. Varaukset ja poissaolot

### GET `/api/citizen/reservations?from=YYYY-MM-DD&to=YYYY-MM-DD`

```json
{
  "children": [
    {
      "id": "<uuid>",
      "firstName": "Etunimi",
      "lastName": "Sukunimi",
      "imageId": "<uuid> | null",
      "upcomingPlacementUnitName": "Päiväkotinimi",
      "displayName": "Kutsumanimi Sukunimi"
    }
  ],
  "days": [
    {
      "date": "2026-05-05",
      "holiday": false,
      "children": [
        {
          "childId": "<uuid>",
          "scheduleType": "RESERVATION_REQUIRED" | "FIXED_SCHEDULE" | "TERM_BREAK",
          "shiftCare": false,
          "reservationsClosed": false,
          "absence": null | {
            "type": "SICKLEAVE" | "OTHER_ABSENCE" | "PLANNED_ABSENCE",
            "editable": true
          },
          "reservations": [
            { "type": "TIMES", "start": "08:00", "end": "16:00" }
          ]
        }
      ]
    }
  ],
  "reservableRange": { "start": "2026-04-27", "end": "2026-06-13" }
}
```

### POST `/api/citizen/reservations`
Varauksen luonti tai poisto. Body on **array**.

```json
// Varauksen asetus
[{
  "type": "RESERVATIONS",
  "childId": "<uuid>",
  "date": "2026-05-05",
  "reservation": { "start": "08:00:00", "end": "16:00:00" },
  "secondReservation": null
}]

// Varauksen tyhjennys (ennen poissaoloa!)
[{ "type": "NOTHING", "childId": "<uuid>", "date": "2026-05-05" }]
```

### POST `/api/citizen/absences`
Poissaolon merkintä. **Huom:** jos päivälle on jo varaus, lähetä ensin
`NOTHING`-varaus (ks. yllä) ennen tätä kutsua.

```json
{
  "childIds": ["<uuid>"],
  "dateRange": { "start": "2026-05-05", "end": "2026-05-05" },
  "absenceType": "OTHER_ABSENCE" | "SICKLEAVE" | "PLANNED_ABSENCE" | "UNKNOWN_ABSENCE"
}
```

---

## 5. Kalenteritapahtumat

### GET `/api/citizen/calendar-events?start=YYYY-MM-DD&end=YYYY-MM-DD`

```json
[
  {
    "id": "<uuid>",
    "title": "Eväsretki",
    "description": "...",
    "period": { "start": "2026-05-10", "end": "2026-05-10" },
    "eventType": "DAYCARE_EVENT" | "DISCUSSION_SURVEY",
    "attendingChildren": {
      "<childId>": [{
        "type": "GROUP" | "INDIVIDUAL",
        "groupName": "Muruset",
        "unitName": "Pikkutuulen päiväkoti",
        "periods": [{ "start": "...", "end": "..." }]
      }]
    },
    "timesByChild": {
      "<eligibleChildId>": [
        {
          "id": "<slotId>",
          "date": "2026-05-15",
          "startTime": "09:00",
          "endTime": "09:30",
          "childId": null,
          "isEditable": true
        }
      ]
    }
  }
]
```

`timesByChild` on relevantti vain `DISCUSSION_SURVEY`-tapahtumille:
- `childId == null` → vapaa aika
- `childId == eligibleChildId` → lapsi on varannut tämän ajan
- `isEditable: false` → varauksen muokkaaminen ei ole enää sallittu

### POST `/api/citizen/calendar-event/reservation`
Varaa keskusteluaika.

```json
{ "calendarEventTimeId": "<slotId>", "childId": "<uuid>" }
```

### DELETE `/api/citizen/calendar-event/reservation?calendarEventTimeId=<slotId>&childId=<uuid>`
Peruuttaa aiemmin varatun ajan. Parametrit query-stringissä.

---

## 6. Poissaolokysely

### GET `/api/citizen/holiday-period/questionnaire`

```json
[
  {
    "questionnaire": {
      "id": "<uuid>",
      "type": "OPEN_RANGES",
      "title": { "fi": "Kesäajan 2026 poissaolokysely", "sv": "", "en": "..." },
      "description": { "fi": "...", "sv": "", "en": "..." },
      "descriptionLink": { "fi": "https://...", "sv": "", "en": "..." },
      "active": { "start": "2026-04-27", "end": "2026-05-10" },
      "period": { "start": "2026-06-01", "end": "2026-08-31" },
      "absenceType": "FREE_ABSENCE",
      "absenceTypeThreshold": 42,
      "periods": [{ "start": "2026-06-01", "end": "2026-08-31" }]
    },
    "eligibleChildren": {
      "<childId>": [{ "start": "2026-06-01", "end": "2026-08-31" }]
    },
    "previousAnswers": [
      {
        "childId": "<childId>",
        "openRanges": [{ "start": "2026-07-01", "end": "2026-07-31" }]
      }
    ]
  }
]
```

`active`-kenttä kertoo milloin kyselyyn voi vastata.  
`period` kertoo mille ajalle poissaoloja ilmoitetaan.  
`previousAnswers` sisältää jo tallennetut vastaukset (voidaan esitäyttää lomake).

### POST `/api/citizen/holiday-period/questionnaire/open-range/<questionnaireId>`
Tallentaa vastaukset `OPEN_RANGES`-kyselyyn.

```json
{
  "openRanges": {
    "<childId>": [
      { "start": "2026-07-01", "end": "2026-07-31" }
    ],
    "<childId2>": [
      { "start": "2026-06-15", "end": "2026-07-15" },
      { "start": "2026-08-01", "end": "2026-08-15" }
    ]
  }
}
```

Yksi lapsi voi ilmoittaa useamman poissaolojakson. Tyhjä lista `[]` = ei poissaoloja.  
Vastaus `204 No Content`.

### POST `/api/citizen/holiday-period/questionnaire/fixed-period/<questionnaireId>`
Käytetään `FIXED_PERIOD`-tyyppisessä kyselyssä (ei tällä hetkellä toteutettu UI:ssa).

```json
{
  "fixedPeriods": {
    "<childId>": { "start": "2026-07-01", "end": "2026-07-31" }
  }
}
```

---

## 7. Loma-ajat

### GET `/api/citizen/holiday-period`
Lista kaikista loma-ajoista (historiallinen + tuleva).

```json
[
  {
    "id": "<uuid>",
    "period": { "start": "2026-03-02", "end": "2026-03-08" },
    "reservationsOpenOn": "2026-01-19",
    "reservationDeadline": "2026-01-28"
  }
]
```

---

## 8. Muut (etusivun badget)

Nämä haetaan mutta niitä ei vielä näytetä sovelluksessa:

| Endpoint | Kuvaus |
|---|---|
| `GET /api/citizen/pedagogical-documents/unread-count` | Lukemattomat pedagogiset dokumentit |
| `GET /api/citizen/child-documents/unread-count` | Lukemattomat lapsiasiakirjat |
| `GET /api/citizen/child-documents/unanswered` | Vastaamattomat asiakirjat |
| `GET /api/citizen/applications/by-guardian/notifications` | Hakemuksen muutokset |
| `GET /api/citizen/daily-service-time-notifications` | Palveluaikailmoitukset |
| `GET /api/citizen/income/expiring` | Tuloselvityksen vanhentuminen |

---

## Virhekäsittely

| HTTP-status | Tilanne | Sovelluksen toiminta |
|---|---|---|
| `200–299` | Onnistui | Normaali käsittely |
| `401` | Sessio vanhentunut | Interceptori tekee re-loginin, toistaa pyynnön |
| `400–499` | Asiakasvirhe | DioException, screen näyttää "Yritä uudelleen" |
| `500+` | Palvelinvirhe | DioException, screen näyttää "Yritä uudelleen" |

> Huom: `validateStatus` hyväksyy koodit < 500 ilman poikkeusta.
> 401 muutetaan poikkeukseksi interceptorissa erikseen.
