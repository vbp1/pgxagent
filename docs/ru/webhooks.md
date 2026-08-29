# Интеграция с вебхуками

XAgent поддерживает приём алертов от внешних систем мониторинга через вебхуки. При получении алерта агент заводит запись об инциденте, запускает плейбук для расследования и создаёт инцидентный чат с результатами.

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
                              │  3. Запись об         │
                              │     инциденте         │
                              │  4. Запуск плейбука   │
                              │  5. Создание чата     │
                              └───────────────────────┘
                                          │
                        ┌─────────────────┴─────────────────┐
                        ▼                                   ▼
            ┌───────────────────────┐          ┌───────────────────────┐
            │   Инцидентный чат     │          │  Раздел Alerts        │
            │   с результатами      │          │  и сообщение в Slack  │
            │   расследования       │          │  (если настроен)      │
            └───────────────────────┘          └───────────────────────┘
```

## Настройка

### 1. Создание конфигурации вебхука

1. Откройте проект в XAgent
2. Перейдите в **Webhooks** в боковом меню
3. Нажмите **Add Webhook**
4. Настройте параметры:

   | Поле                       | Что задаёт                                                                                                    |
   | -------------------------- | --------------------------------------------------------------------------------------------------------------- |
   | **Name**                   | Уникальный идентификатор (snake_case, например `alertmanager_prod`)                                           |
   | **Playbook**               | Плейбук расследования; для алертов подходит `generalTroubleshooting`                                          |
   | **Model**                  | LLM-модель для выполнения                                                                                     |
   | **Hostname Label**         | Лейбл AlertManager с именем хоста базы (по умолчанию `instance`)                                              |
   | **Severity Label**         | Лейбл с серьёзностью алерта (по умолчанию `severity`). Незнакомое значение агент уточнит по итогам расследования |
   | **Flap Window**            | Окно в минутах (1-1440, по умолчанию 5): если та же проблема сообщена снова в течение этого времени после отбоя, она возвращается в прежнюю запись, а не открывает новую |
   | **Notify Level**           | Минимальный уровень, начиная с которого уходит уведомление в Slack                                             |
   | **Keep History**           | Сколько запусков вебхука хранить в истории (1-1000)                                                            |
   | **Max Steps**              | Сколько раз расследование может вызвать другие плейбуки; допустимо от 1 до 50, при 1 выполняется только выбранный |
   | **Additional Instructions**| Дополнительные указания плейбуку. Поле нельзя оставлять пустым при создании - см. [known-issues.md](known-issues.md) |
   | **Allow SQL diagnostics**  | Разрешает расследованию инструменты запросов к базе. **Включено по умолчанию**; выключите, если расследование не должно обращаться к данным |
   | **MCP access**             | Какие MCP-серверы доступны расследованию; всегда в пределах доступного создателю вебхука                       |
   | **Enabled**                | Включение и выключение вебхука                                                                                |

5. Нажмите **Create Webhook**

### 2. Создание API-токена

1. На странице вебхука найдите раздел **API Tokens**
2. Нажмите **Create Token**
3. Введите имя (например, "AlertManager Production")
4. Скопируйте токен сразу: он показывается только один раз.

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
3. Агент ищет узел сервера, у которого сохранённое имя машины (поле **Machine Name**) совпадает с этим значением - это быстрый поиск по индексу в пределах проекта, **без** обращения к самим базам. Если это имя хоста носят несколько наблюдаемых баз, берётся добавленная раньше остальных - см. [known-issues.md](known-issues.md)
4. При совпадении плейбук запускается на этом сервере; для кластера расследование привязывается к узлу, на котором сработал алерт, с доступом к контексту всего кластера

**Настройка лейбла hostname:**

- Если алерты используют другой лейбл (например, `host`, `node`, `server`), измените поле **Hostname Label** в конфигурации вебхука

**Убедитесь, что у сервера задано имя хоста (Machine Name):**

Сопоставление идёт по имени хоста, сохранённому у сервера (поле **Machine Name**), а не по запросу к базе. Его задают вручную при создании или редактировании сервера - укажите то же имя, которое приходит в лейбле алерта (см. раздел «Имя машины (Machine Name)» в quick-start.md).

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

- `received` - сколько алертов пришло в запросе
- `runs` - по одному элементу на каждое заведённое расследование
- `skipped` - алерты, по которым расследование не заводится; каждый элемент содержит `alertName`, `fingerprint` и `reason` (тексты причин - в разделе «Обработка алертов»)

**Ошибки:**

- `401 Unauthorized` - отсутствует или невалидный токен
- `403 Forbidden` - токен не соответствует конфигурации; вебхук выключен; создатель заблокирован или больше не участник проекта; либо его роль больше не даёт работать с серверами и запускать плейбуки (например, после понижения до **viewer**)
- `404 Not Found` - конфигурация вебхука не найдена
- `400 Bad Request` - невалидный формат payload

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

- `pending` - ожидает в очереди
- `running` - плейбук выполняется
- `completed` - завершён успешно
- `failed` - произошла ошибка (см. `errorMessage`)

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

Всё держится на **записи об инциденте** (раздел **Alerts**). Запись открывается один раз и один раз закрывается; повторные сигналы с тем же `fingerprint` дописываются в неё, а не порождают новые расследования. Записи видны в разделе **Alerts**, и при настроенной интеграции со Slack их открытие и закрытие уходят в канал.

### Firing-алерты

1. Из алерта читается имя хоста (лейбл **Hostname Label**) и серьёзность (лейбл **Severity Label**)
2. Имя хоста сопоставляется с узлом сервера
3. Открывается новая запись об инциденте по `fingerprint` - либо подтверждается уже открытая, либо возобновляется закрытая, если отбой по ней был не раньше, чем **Flap Window** минут назад
4. Для новой записи заводится расследование: выполняется настроенный плейбук и создаётся инцидентный чат

Что происходит с повторными сигналами:

| Ситуация                                                       | Ответ в `skipped`                                                                            |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Проблема уже открыта                                           | `already recorded — the problem is still open`                                                 |
| Проблема вернулась внутри окна мерцания, расследование уже есть | `recorded on the record it came back to — that record already has its investigation`            |
| Сигнал старше уже закрытой записи с тем же `fingerprint`        | `refused — this signal is older than the problem already settled under the same fingerprint`    |

Возврат проблемы внутри окна мерцания дополнительно сообщается в канал и в инцидентный чат - чтобы «отбой», отправленный ранее, не остался последним словом.

### Resolved-алерты

Resolved-алерт закрывает запись. Новое расследование не создаётся, ответ - `202 Accepted`, а сам алерт попадает в `skipped` с причиной, описывающей исход:

| Ситуация                                                    | Ответ в `skipped`                                                              |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Запись закрыта                                              | `resolved - the record is closed`                                                |
| Отбой по этой проблеме уже был получен                      | `resolved - this all-clear has already been recorded`                            |
| Отбой относится к прошлому эпизоду, а текущий ещё открыт    | `resolved - this all-clear is about an earlier spell of trouble; a later one is still open` |
| Под этим `fingerprint` ничего открытого не было             | `resolved - nothing was open under this fingerprint`                             |
| Запись закрыта, но о самой проблеме в канал не сообщалось   | `resolved - recorded, though the problem itself was never reported`              |

При закрытии записи закрывающая заметка добавляется в инцидентный чат, а в Slack уходит сообщение о том, что проблема ушла. Весь контекст инцидента остаётся в одном чате.

## Управление параллелизмом

Агент ограничивает количество одновременных расследований, чтобы не перегружать установку:

- По умолчанию: 3 расследования одновременно; задаётся переменной окружения `WEBHOOK_MAX_PARALLEL_RUNS`
- Предел считается на всю установку, сколько бы копий сервиса ни было запущено
- Остальные алерты ожидают в очереди и разбираются в порядке поступления

## Диагностика проблем

### Алерт не запускает плейбук

1. **Проверьте, что вебхук включён** - выключенные вебхуки возвращают 403
2. **Проверьте токен** - убедитесь, что токен соответствует конфигурации вебхука
3. **Проверьте сопоставление hostname** - используйте кнопку Test на странице вебхука
4. **Просмотрите историю запусков** - проверьте таблицу Runs на наличие ошибок

### Не найден подходящий сервер

Hostname в алерте должен точно совпадать с именем хоста (**Machine Name**), заданным у узла одного из ваших серверов.

Шаги диагностики:

1. Проверьте, какой hostname отправляет AlertManager (посмотрите лейблы алерта)
2. Убедитесь, что настройка hostname label совпадает с лейблами алертов
3. Используйте функцию Test для проверки сопоставления hostname
4. Проверьте поле **Machine Name** у сервера в разделе **Targets** - именно оно сопоставляется с алертом; задайте в нём то же имя, что приходит в лейбле алерта

### Токен не работает

- Токен показывается только один раз при создании - если потерян, создайте новый
- Убедитесь в формате заголовка: `Authorization: Bearer <token>`
- Токен должен принадлежать конкретной конфигурации вебхука в URL

## Тестирование через curl

Вебхук можно проверить без AlertManager, обычным curl.

### Что нужно

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
- **WEBHOOK_TOKEN**: копируется при создании нового токена (показывается только один раз). Если потерян - создайте новый в разделе Tokens.
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
| Повторный алерт с тем же fingerprint        | 202, алерт пропущен: запись уже открыта                |
| Пустой массив alerts                       | 400 Bad Request                                        |

## Контекст выполнения

При запуске плейбука через вебхук агент работает **от имени пользователя, создавшего вебхук**:

- **Инструменты**: все AI-инструменты (MCP-серверы, запросы к БД, доступ к метрикам и т.д.) используют права создателя вебхука
- **Владение чатом**: инцидентный чат принадлежит создателю вебхука
- **Контроль доступа**: создатель должен быть участником проекта с соответствующими правами

**Важные следствия:**

1. Если создатель вебхука будет удалён из проекта или потеряет право работать с серверами и запускать плейбуки, выполнение вебхука завершится ошибкой
2. Доступ создателя к подключённым ресурсам (MCP-серверы, облачные провайдеры) определяет возможности агента
3. Инцидентные чаты отображаются в аккаунте создателя

Поэтому вебхук не даёт больше прав, чем есть у его создателя, по журналу видно, кто настроил автоматические действия, и права работают так же, как в обычном чате.

## Безопасность

- Токены хранятся как SHA-256 хеши (никогда в открытом виде)
- Каждый токен привязан к одной конфигурации вебхука
- Выключенные вебхуки возвращают 403 (не тихий пропуск)
- Payload строго валидируется по схеме AlertManager
- Все операции подчиняются контролю доступа на уровне проекта
- **Выполнение вебхука использует права создателя** (см. раздел «Контекст выполнения»)
