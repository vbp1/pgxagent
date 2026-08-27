# Интеграция с вебхуками

XAgent поддерживает приём алертов от внешних систем мониторинга через вебхуки. При получении алерта агент автоматически запускает плейбук для расследования проблемы и создаёт инцидентный чат с результатами.

## Общая схема

```
┌─────────────────────┐     POST /api/projects/{id}/webhooks/{configId}/alerts
│   AlertManager      │ ──────────────────────────────────────────────────────►
│   (или другая       │     Authorization: Bearer xagent_wh_xxxxx
│    система)         │
└─────────────────────┘
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │     XAgent            │
                              │                       │
                              │  1. Проверка токена   │
                              │  2. Сопоставление     │
                              │     hostname          │
                              │  3. Запуск плейбука   │
                              │  4. Создание чата     │
                              └───────────────────────┘
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │   Инцидентный чат     │
                              │   с результатами      │
                              │   расследования       │
                              └───────────────────────┘
```

## Настройка

### 1. Создание конфигурации вебхука

1. Откройте проект в XAgent
2. Перейдите в **Webhooks** в боковом меню
3. Нажмите **Add Webhook**
4. Настройте параметры:
   - **Name**: уникальный идентификатор (snake_case, например `alertmanager_prod`)
   - **Playbook**: выберите `generalTroubleshooting` для расследования алертов
   - **Model**: LLM-модель для выполнения
   - **Hostname Label**: лейбл AlertManager, содержащий hostname базы данных (по умолчанию: `instance`)
   - **Max Steps**: максимальное количество шагов плейбука
   - **Enabled**: переключатель включения/выключения вебхука

5. Нажмите **Create Webhook**

### 2. Создание API-токена

1. На странице вебхука найдите раздел **API Tokens**
2. Нажмите **Create Token**
3. Введите имя (например, "AlertManager Production")
4. **Важно**: скопируйте токен сразу — он будет показан только один раз!

Формат токена: `xagent_wh_<64 hex-символа>`

### 3. Получение URL вебхука

URL вебхука отображается на странице конфигурации:

```
POST {PUBLIC_URL}/api/projects/{projectId}/webhooks/{configId}/alerts
```

### 4. Настройка AlertManager

Добавьте webhook-receiver в конфигурацию AlertManager:

```yaml
# alertmanager.yml
receivers:
  - name: 'xagent'
    webhook_configs:
      - url: 'https://your-xagent.example.com/api/projects/PROJECT_ID/webhooks/CONFIG_ID/alerts'
        http_config:
          authorization:
            type: Bearer
            credentials: 'xagent_wh_your_token_here'
        send_resolved: true

route:
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'xagent'
    - match:
        severity: warning
      receiver: 'xagent'
```

### 5. Сопоставление hostname

Агент сопоставляет алерты с серверами (targets) по hostname. По умолчанию используется лейбл `instance` из алерта.

**Как это работает:**

1. Приходит алерт с лейблами (например, `instance: "db-prod-01"`)
2. Агент извлекает hostname из настроенного лейбла
3. Агент ищет узел сервера, у которого сохранённое имя хоста (`target_nodes.hostname`) совпадает с этим значением — это быстрый поиск по индексу в пределах проекта, **без** обращения к самим базам
4. При совпадении плейбук запускается на этом сервере; для кластера расследование привязывается к узлу, на котором сработал алерт, с доступом к контексту всего кластера

**Настройка лейбла hostname:**

- Если алерты используют другой лейбл (например, `host`, `node`, `server`), измените поле **Hostname Label** в конфигурации вебхука

**Убедитесь, что у сервера задано имя хоста (Machine Name):**

Сопоставление идёт по имени хоста, сохранённому у сервера (поле **Machine Name**), а не по запросу к базе. Его задают вручную при создании или редактировании сервера — укажите то же имя, которое приходит в лейбле алерта (см. раздел «Имя машины (Machine Name)» в quick-start.md).

## Справочник API

### Отправка алерта

Принимает алерты от AlertManager и запускает выполнение плейбука.

```
POST /api/projects/{projectId}/webhooks/{configId}/alerts
Authorization: Bearer xagent_wh_xxxxx
Content-Type: application/json
```

**Тело запроса** (формат webhook AlertManager):

```json
{
  "version": "4",
  "groupKey": "{}:{alertname=\"HighCPU\"}",
  "status": "firing",
  "receiver": "xagent",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "HighCPU",
        "instance": "db-prod-01",
        "severity": "critical"
      },
      "annotations": {
        "summary": "High CPU usage detected",
        "description": "CPU usage is above 90% for 5 minutes"
      },
      "startsAt": "2024-01-15T10:00:00Z",
      "fingerprint": "abc123def456"
    }
  ]
}
```

**Ответ** (202 Accepted):

```json
{
  "received": 1,
  "runs": [
    {
      "runId": "uuid-xxx",
      "alertName": "HighCPU",
      "hostname": "db-prod-01",
      "status": "pending"
    }
  ],
  "skipped": []
}
```

**Ошибки:**

- `401 Unauthorized` — отсутствует или невалидный токен
- `403 Forbidden` — токен не соответствует конфигурации; вебхук выключен; или его создатель заблокирован / больше не участник проекта
- `404 Not Found` — конфигурация вебхука не найдена
- `400 Bad Request` — невалидный формат payload

### Проверка статуса запуска

Проверка статуса webhook-запуска и получение URL инцидентного чата.

```
GET /api/projects/{projectId}/webhooks/runs/{runId}
Authorization: Bearer xagent_wh_xxxxx
```

**Ответ**:

```json
{
  "runId": "uuid-xxx",
  "status": "completed",
  "alertName": "HighCPU",
  "alertFingerprint": "abc123def456",
  "hostnameReceived": "db-prod-01",
  "hostnameMatched": "db-prod-01",
  "chatId": "uuid-chat",
  "chatUrl": "https://agent.example.com/projects/xxx/chats/uuid-chat",
  "errorMessage": null,
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:05:00Z"
}
```

**Статусы запуска:**

- `pending` — ожидает в очереди
- `running` — плейбук выполняется
- `completed` — завершён успешно
- `failed` — произошла ошибка (см. `errorMessage`)

### Тест сопоставления hostname (внутренний)

Пробный запуск сопоставления hostname без выполнения плейбука. Требует аутентификацию через сессию.

```
POST /api/projects/{projectId}/webhooks/{configId}/test
Content-Type: application/json

{
  "hostname": "db-prod-01"
}
```

**Ответ**:

```json
{
  "matched": true,
  "targetId": "uuid-target",
  "targetName": "Production DB",
  "targetNodeId": "uuid-node",
  "matchedHostname": "db-prod-01"
}
```

## Обработка алертов

### Firing-алерты

При получении firing-алерта:

1. Проверка дубликатов (пропуск, если тот же fingerprint уже в статусе pending/running)
2. Создание записи о запуске
3. Сопоставление hostname с сервером (target)
4. Выполнение настроенного плейбука
5. Создание инцидентного чата с результатами расследования

### Resolved-алерты

При получении resolved-алерта:

1. Поиск существующего firing-запуска с тем же fingerprint
2. Если найден и есть чат — добавление сообщения "Alert Resolved" в чат; алерт попадает в `skipped` с причиной `resolved - added message to existing chat`
3. Если не найден — алерт попадает в `skipped` с причиной `resolved - no existing firing alert found`

В обоих случаях ответ — `202 Accepted` (новый запуск не создаётся). Это сохраняет весь контекст инцидента в одном чате.

## Управление параллелизмом

Агент ограничивает количество одновременных запусков плейбуков для предотвращения перегрузки:

- По умолчанию: 3 параллельных плейбука
- Дополнительные алерты ожидают в очереди
- Очередь обрабатывается в порядке FIFO

## Диагностика проблем

### Алерт не запускает плейбук

1. **Проверьте, что вебхук включён** — выключенные вебхуки возвращают 403
2. **Проверьте токен** — убедитесь, что токен соответствует конфигурации вебхука
3. **Проверьте сопоставление hostname** — используйте кнопку Test на странице вебхука
4. **Просмотрите историю запусков** — проверьте таблицу Runs на наличие ошибок

### Не найден подходящий сервер

Hostname в алерте должен точно совпадать с именем хоста (**Machine Name**), заданным у узла одного из ваших серверов.

Шаги диагностики:

1. Проверьте, какой hostname отправляет AlertManager (посмотрите лейблы алерта)
2. Убедитесь, что настройка hostname label совпадает с лейблами алертов
3. Используйте функцию Test для проверки сопоставления hostname
4. Проверьте поле **Machine Name** у сервера в разделе **Targets** — именно оно сопоставляется с алертом; задайте в нём то же имя, что приходит в лейбле алерта

### Токен не работает

- Токен показывается только один раз при создании — если потерян, создайте новый
- Убедитесь в формате заголовка: `Authorization: Bearer <token>`
- Токен должен принадлежать конкретной конфигурации вебхука в URL

## Тестирование через curl

Функциональность вебхуков можно проверить без AlertManager, используя curl.

### Предварительные требования

1. Создайте конфигурацию вебхука в UI
2. Создайте API-токен и скопируйте его
3. Убедитесь, что у сервера задано поле **Machine Name** (см. quick-start.md)
4. Используйте это же значение как hostname в тестовом алерте

### Настройка переменных окружения

```bash
# Замените на ваши значения
export XAGENT_URL="http://localhost:4001"
export PROJECT_ID="your-project-uuid"
export WEBHOOK_CONFIG_ID="your-webhook-config-uuid"
export WEBHOOK_TOKEN="xagent_wh_your_token_here"
export DB_HOSTNAME="your-db-hostname"
```

**Где найти эти значения:**

- **PROJECT_ID**: в URL при просмотре проекта. Пример: `/projects/550e8400-e29b-41d4-a716-446655440000/...` → UUID после `/projects/`
- **WEBHOOK_CONFIG_ID**: перейдите в **Webhooks** → кликните на конфигурацию. URL будет вида `/projects/.../webhooks/6ba7b810-9dad-11d1-80b4-00c04fd430c8` → последний UUID. Также отображается на странице конфигурации.
- **WEBHOOK_TOKEN**: копируется при создании нового токена (показывается только один раз). Если потерян — создайте новый в разделе Tokens.
- **DB_HOSTNAME**: значение поля **Machine Name** у сервера (раздел **Targets**), либо проверьте в разделе Test на странице вебхука.

### Отправка тестового firing-алерта

Минимальный payload (остальные поля генерируются автоматически):

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "firing",
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'"
        }
      }
    ]
  }'
```

Полный payload (все поля указаны):

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "4",
    "groupKey": "{}:{alertname=\"TestAlert\"}",
    "status": "firing",
    "receiver": "xagent",
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'",
          "severity": "warning"
        },
        "annotations": {
          "summary": "Test alert from curl",
          "description": "This is a manual test alert to verify webhook integration"
        },
        "startsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
        "fingerprint": "test-'"$(date +%s)"'"
      }
    ]
  }'
```

**Ожидаемый ответ** (202 Accepted):

```json
{
  "received": 1,
  "runs": [
    {
      "runId": "uuid-xxx",
      "alertName": "TestAlert",
      "hostname": "your-db-hostname",
      "status": "pending"
    }
  ],
  "skipped": []
}
```

### Проверка статуса запуска

Скопируйте `runId` из ответа и проверьте статус:

```bash
export RUN_ID="uuid-from-previous-response"

curl "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/runs/${RUN_ID}" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}"
```

**Ответ при завершении**:

```json
{
  "runId": "uuid-xxx",
  "status": "completed",
  "alertName": "TestAlert",
  "chatId": "uuid-chat",
  "chatUrl": "http://localhost:4001/projects/xxx/chats/uuid-chat"
}
```

### Отправка resolved-алерта

Для проверки обработки resolved-алертов (добавляет сообщение в существующий инцидентный чат):

```bash
# Используйте тот же fingerprint, что и у firing-алерта
export FINGERPRINT="test-1234567890"

curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "4",
    "groupKey": "{}:{alertname=\"TestAlert\"}",
    "status": "resolved",
    "receiver": "xagent",
    "alerts": [
      {
        "status": "resolved",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'",
          "severity": "warning"
        },
        "annotations": {
          "summary": "Test alert resolved"
        },
        "startsAt": "2024-01-15T10:00:00Z",
        "endsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
        "fingerprint": "'"${FINGERPRINT}"'"
      }
    ]
  }'
```

### Тест сопоставления hostname

Проверка, будет ли hostname сопоставлен с сервером, без запуска плейбука:

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/test" \
  -H "Content-Type: application/json" \
  -H "Cookie: your-session-cookie" \
  -d '{
    "hostname": "'"${DB_HOSTNAME}"'"
  }'
```

Примечание: эндпоинт тестирования требует аутентификацию через сессию (cookie браузера), а не токен.

### Типичные тестовые сценарии

| Сценарий                                   | Ожидаемый результат                                    |
| ------------------------------------------ | ------------------------------------------------------ |
| Валидный токен, совпадающий hostname       | 202, запуск создан                                     |
| Невалидный токен                           | 401 Unauthorized                                       |
| Валидный токен, неверная конфигурация      | 403 Forbidden                                          |
| Выключенный вебхук                         | 403 Forbidden                                          |
| Hostname не совпадает ни с одним сервером | 202, запуск создан, но завершится с ошибкой "No usable target found" |
| Дублирующийся fingerprint (pending/running)| 202, алерт пропущен                                   |
| Пустой массив alerts                       | 400 Bad Request                                        |

## Контекст выполнения

При запуске плейбука через вебхук агент работает **от имени пользователя, создавшего вебхук**:

- **Инструменты**: все AI-инструменты (MCP-серверы, запросы к БД, доступ к метрикам и т.д.) используют права создателя вебхука
- **Владение чатом**: инцидентный чат принадлежит создателю вебхука
- **Контроль доступа**: создатель должен быть участником проекта с соответствующими правами

**Важные следствия:**

1. Если создатель вебхука будет удалён из проекта, выполнение вебхука завершится ошибкой
2. Доступ создателя к подключённым ресурсам (MCP-серверы, облачные провайдеры) определяет возможности агента
3. Инцидентные чаты отображаются в аккаунте создателя

Такой подход обеспечивает:

- Отсутствие эскалации привилегий через вебхуки
- Полный аудит того, кто настроил автоматические действия
- Единую модель прав с интерактивными чат-сессиями

## Безопасность

- Токены хранятся как SHA-256 хеши (никогда в открытом виде)
- Каждый токен привязан к одной конфигурации вебхука
- Выключенные вебхуки возвращают 403 (не тихий пропуск)
- Payload строго валидируется по схеме AlertManager
- Все операции подчиняются контролю доступа на уровне проекта
- **Выполнение вебхука использует права создателя** (см. раздел «Контекст выполнения»)
