# Sapiens4 `dev` — Linter4: slop, FP, ADT и проблемы типизации

**Источник:** [`aleski-green/sapiens4`, ветка `dev`](https://github.com/aleski-green/sapiens4/tree/dev)  
**Проверенная ревизия:** [`7ae482545bfe4454168d7af48a94e4063cc8188e`](https://github.com/aleski-green/sapiens4/commit/7ae482545bfe4454168d7af48a94e4063cc8188e)  
**Метод:** статический просмотр выбранных исходников. Это не полный прогон компилятора, тестов или линтера. Ряд находок — потенциальные code smells, а не подтверждённые ошибки выполнения.

## 1. Silent fallback — скрытие ошибок типов

**Описание:** Вместо ошибки при неправильном JSON-типе код возвращает `""`, `0` или `False`. Если этот путь используется без предварительной валидации, некорректные данные выглядят корректными.

**Код:**

```haskell
text (String s) = s
text _ = ""

int (Number n) = fromMaybe 0 (toBoundedInteger n)
int _ = 0

boolean (Bool b) = b
boolean _ = False
```

**Ссылка:** [Domain.hs — функции `text`, `int`, `boolean`](https://github.com/aleski-green/sapiens4/blob/dev/corpora/state/Domain.hs#L192-L204)

**Статус:** потенциально критично при отсутствии отдельной строгой проверки. **Кастомный линтер:** да, с контекстом использования.

## 2. Обязательные поля проверяются как необязательные

**Описание:** Валидатор `Turn` использует `optional` для `id` и `status`, хотя итоговая модель имеет обязательные поля. При отсутствии поля декодер может подставить дефолт вместо отклонения ответа.

**Код (фрагмент):**

```purescript
checkTurn = record
  [ optional "id" stringValue
  , optional "status" stringValue
  -- другие проверки
  ]
```

**Ссылки:** [Domain.purs — `checkTurn`](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/model/Domain.purs#L587-L590) · [Domain.purs — тип и декодер `Turn`](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/model/Domain.purs#L119-L140)

**Статус:** несоответствие между схемой и моделью. **Кастомный линтер:** возможно, через сравнение декодера и схемы.

## 3. Ошибка JSON превращается в `Null`

**Описание:** Неудачное декодирование превращается в `Null`; вызывающий код не может отличить ошибку парсинга от корректного JSON `null`.

**Код:**

```haskell
parseJSONText :: Text -> Value
parseJSONText = fromMaybe Null . decode . BL.fromStrict . TE.encodeUtf8
```

**Ссылка:** [Domain.hs — `parseJSONText`](https://github.com/aleski-green/sapiens4/blob/dev/corpora/state/Domain.hs#L235-L242)

**Статус:** потенциальная потеря ошибки; зависит от контракта функции. **Кастомный линтер:** да.

## 4. Динамический JSON внутри доменной модели

**Описание:** Часть полей `Turn` типизирована через ADT, но `turnFields :: Object` остаётся динамическим. Строковые ключи и типы дополнительных полей не контролируются компилятором. Это может быть осознанным решением для расширяемых metadata.

**Код (сокращённый фрагмент):**

```haskell
data Turn = Turn
  { turnId :: RunId
  , turnFlow :: Flow
  , turnInput :: Text
  , turnStatus :: TurnStatus
  , turnAttempt :: Maybe Int
  , turnBatchId :: Maybe RunId
  , turnFields :: Object
  }
```

**Ссылка:** [Domain.hs — `Turn`](https://github.com/aleski-green/sapiens4/blob/dev/corpora/state/Domain.hs#L122-L134)

**Статус:** архитектурный компромисс, не автоматический баг. **Кастомный линтер:** да, через правила по слоям/модулям.

## 5. `String` вместо существующего ADT

**Описание:** Haskell-модель использует ADT `Flow = Chat | Computer`, тогда как в PureScript поле `flow` имеет тип `String`. Это допускает произвольные состояния, которые компилятор не может исключить.

**Код (фрагменты):**

```haskell
data Flow = Chat | Computer
```

```purescript
type Turn =
  { id :: String
  , flow :: String
  , status :: CallState
  -- другие поля
  }
```

**Ссылки:** [Haskell — `Flow`](https://github.com/aleski-green/sapiens4/blob/dev/corpora/state/Domain.hs#L62-L65) · [PureScript — `Turn`](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/model/Domain.purs#L119-L140)

**Статус:** потеря точности типов. **Кастомный линтер:** частично, через поиск полей с ограниченным набором литералов.

## 6. `unsafePerformEffect` и глобальное изменяемое состояние

**Описание:** Глобальная ссылка создаётся через `unsafePerformEffect`, что обходит явное управление эффектом. Такой подход иногда оправдан в браузерном адаптере, но требует ревью.

**Код:**

```purescript
installEvent :: Ref.Ref (Maybe Event)
installEvent = unsafePerformEffect $ Ref.new Nothing
```

**Ссылка:** [BrowserNative.purs — `installEvent`](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/interaction/BrowserNative.purs#L211-L213)

**Статус:** FP code smell, не доказанный баг. **Кастомный линтер:** да.

## 7. `IO` для логики парсинга

**Описание:** Функции разбора событий возвращают `IO [ProviderEvent]`, хотя логика сопоставления JSON и конструкторов событий потенциально может быть чистой и возвращать `Either ParseError [ProviderEvent]`.

**Код:**

```haskell
claudeEvents :: Value -> IO [ProviderEvent]
agyEvents :: Value -> IO [ProviderEvent]
```

**Ссылка:** [Provider.hs — парсинг событий](https://github.com/aleski-green/sapiens4/blob/dev/corpora/work/Provider.hs#L155-L182)

**Статус:** возможное упрощение архитектуры. **Кастомный линтер:** частично, нужен анализ вызываемых функций.

## 8. Polling вместо ожидания события

**Описание:** При подключении клиент проверяет состояние в цикле с задержкой 10 мс (до 1000 повторений). Событийное уведомление могло бы избежать частого polling, если транспорт предоставляет надёжный сигнал.

**Код (фрагмент):**

```purescript
wait version 1000

-- Внутри wait:
_ | count <= 0 -> ...
  | otherwise -> delay (Milliseconds 10.0) *> wait version (count - 1)
```

**Ссылка:** [Remote.purs — ожидание подключения](https://github.com/aleski-green/sapiens4/blob/dev/app/features/Remote.purs#L250-L259)

**Статус:** возможная оптимизация, не доказанный баг. **Кастомный линтер:** может сигнализировать о polling, но не определять корректную замену автоматически.

## 9. Широкое подавление исключений

**Описание:** При чтении сохранённой Relay-конфигурации `SomeException` превращается в пропуск записи. Это может скрывать неожиданные ошибки наряду с допустимыми проблемами чтения.

**Код:**

```haskell
case old of
  Left (_ :: SomeException) -> pure (rows, selected)
  Right connection -> ...
```

**Ссылка:** [Registry.hs — чтение Relay-конфигурации](https://github.com/aleski-green/sapiens4/blob/dev/remote/control/Registry.hs#L330-L336)

**Статус:** возможное скрытие сбоев, нужен разбор требований восстановления. **Кастомный линтер:** да, как предупреждение.

## 10. Дублирование схемы и декодирования

**Описание:** Одна и та же JSON-модель `Turn` описывается в типе, декодере и отдельном валидаторе. Эти определения нужно синхронизировать вручную; пример №2 показывает их расхождение.

**Код (структурная схема, не дословный фрагмент):**

```purescript
type Turn = { ... }
turn :: Json -> Turn
checkTurn :: Check
```

**Ссылка:** [Domain.purs — типы, декодеры и проверки](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/model/Domain.purs)

**Статус:** дублирование контрактов и риск рассинхронизации. **Кастомный линтер:** частично, через сопоставление схем и полей.

## 11. Повторное сканирование коллекций при построении UI

**Описание:** Для каждого агента UI-модель повторно фильтрует общий список `turns`, чтобы вычислить последнее действие. При росте числа агентов и задач это создаёт дополнительные проходы. Для оценки серьёзности нужен профайлинг.

**Код (сокращённый фрагмент):**

```purescript
personal = map (\a -> a
  { lastActivity = B.parseTime $ D.fallback a.created $
      fromMaybe "" $ _.created <$>
        A.last (A.filter (\t -> t.agent == a.id) turns)
  }) snapshot.agents
```

**Ссылка:** [Model.purs — `projectSnapshot`](https://github.com/aleski-green/sapiens4/blob/dev/app/shell/model/Model.purs#L244-L287)

**Статус:** возможная неэффективность, а не доказанная деградация. **Кастомный линтер:** частично, как эвристика для вложенных проходов.

---

## Сводная таблица

| № | Находка | Предварительная оценка | Проверка кастомным линтером |
|---|---|---|---|
| 1 | Silent fallbacks | No-Go candidate | Да, с контекстом |
| 2 | Обязательные поля как optional | No-Go candidate | Да, со сравнением схем |
| 3 | Ошибка JSON → `Null` | No-Go candidate | Да |
| 4 | Динамический JSON в доменной модели | Warning | Да, с исключениями |
| 5 | `String` вместо ADT | Warning | Частично |
| 6 | `unsafePerformEffect` | Warning | Да |
| 7 | `IO` для парсинга | Warning | Частично |
| 8 | Polling | Warning | Да, как подозрение |
| 9 | Подавление `SomeException` | Warning | Да |
| 10 | Дублирование схем | Warning | Частично |
| 11 | Повторные сканирования | Could Be Better | Частично |

**Важно:** `No-Go candidate` означает кандидата на блокирующее правило, а не доказанный критический баг в этой ревизии. Для реального No-Go нужно подтвердить достижимость опасного пути и отсутствие другой защитной проверки.
