# eVaka Oulu — epävirallinen mobiilisovellus

Epävirallinen Flutter-asiakas Oulun varhaiskasvatuksen eVaka-palvelulle
([varhaiskasvatus.ouka.fi](https://varhaiskasvatus.ouka.fi)).

> **Huom:** Tämä on henkilökohtainen harrastusprojekti. Se ei ole Oulun kaupungin
> tai Espoo Voltin virallinen sovellus eikä ole millään tavalla heidän tukemanaan.

## Ominaisuudet

| Ominaisuus | Tila |
|---|---|
| Kirjautuminen sähköpostilla ja salasanalla | ✅ |
| Viestit — selaus, luku, vastaaminen | ✅ |
| Läsnäolo — varaukset, poissaolot, massailmoitus | ✅ |
| Kalenteri — päiväkotitapahtumat | ✅ |
| Keskusteluaikavaraukset (DISCUSSION_SURVEY) | ✅ |
| Poissaolokysely (kesä ym. loma-ajat) | ✅ |

## Nopea käynnistys

```bash
# Vaatii Flutter SDK ≥ 3.11
flutter pub get
flutter run
```

APK-julkaisukäännös:

```bash
./build_release.sh
```

## Dokumentaatio

| Tiedosto | Sisältö |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Arkkitehtuuri, tiedostorakenne, state management |
| [docs/api.md](docs/api.md) | Kaikki API-endpointit ja rakenteet |
| [docs/features.md](docs/features.md) | Ominaisuuksien toimintaperiaatteet ja laajennusohjeet |

## Tekniset valinnat

- **Flutter** + Dart — cross-platform mobiilikehitys
- **Riverpod** — state management
- **Dio** — HTTP-asiakas, keksien hallinta, automaattinen re-login
- **flutter_secure_storage** — tunnusten turvallinen tallennus
