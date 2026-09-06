# Torly API

Чистый backend-скелет для Torly на Node.js без зависимостей.

Он взят по идее запуска старого scanner-сервера, но очищен от scanner/OpenAI/audio-логики. Сейчас данные живут в памяти, завтра их можно заменить на Supabase/Postgres.

## Продуктовая стратегия

Torly остается легким аналогом Calmark: первые 2 месяца бесплатно, затем основной тариф ₪49/месяц. Внутри API сразу заложены международные настройки, чтобы позже выйти за Израиль без переписывания продукта:

- языки: `en` и `he`;
- валюты: `ILS`, `USD`, `EUR`, `GBP`;
- страны: Израиль, США, Великобритания, Германия, Франция, Испания;
- часовые пояса в формате IANA;
- WhatsApp templates для Hebrew и English;
- Stripe-ready поля для будущей подписки;
- телефоны в E.164.

## Запуск

```bash
npm start
```

По умолчанию сервер слушает `http://127.0.0.1:3100`.

## Основные endpoints

- `GET /health`
- `GET /api/bootstrap` - тариф, страны, валюты, языки, WhatsApp-шаблоны, payment config
- `GET /api/businesses`
- `GET /api/businesses/:slug`
- `GET /api/businesses/:slug/availability?month=2026-09`
- `POST /api/bookings`
- `GET /api/owner/dashboard?businessId=biz_barber_dizengoff`
- `PUT /api/owner/settings`

## Ближайший план

- подключить Supabase Auth;
- перенести массивы в таблицы Postgres;
- добавить RLS: владелец видит свой бизнес, клиент видит свои записи;
- добавить хранение `country_code`, `currency`, `locale`, `timezone`, `phone_e164`;
- добавить realtime-канал календаря;
- добавить WhatsApp reminder worker;
- подключить iPhone-приложение к API;
- подготовить production deploy.
