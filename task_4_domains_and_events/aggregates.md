# Примеры агрегатов

Описание агрегатов согласно Domain-Driven Design (DDD) с указанием границ, инвариантов и ключей.

---

## Медицинские услуги (Клиники)

### Агрегат: Приём пациента (Appointment)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Управление приёмами пациентов |
| **Aggregate Root** | `Appointment` |
| **Идентификатор** | `appointment_id: UUID` |
| **Границы** | Включает: слот времени, врач, пациент, статус, комментарии. Не включает: медицинскую карту, платёжную информацию. |

**Инварианты:**
- Приём не может быть назначен на прошедшее время
- Один врач не может иметь два приёма в одно время
- Статус может меняться только по определённой схеме: `scheduled → confirmed → completed` или `scheduled → cancelled`

**Ключевые атрибуты:**
```
appointment_id: UUID (PK)
patient_id: UUID (FK)
doctor_id: UUID (FK)
clinic_id: UUID (FK)
scheduled_at: DateTime
status: Enum[scheduled, confirmed, in_progress, completed, cancelled]
created_at: DateTime
updated_at: DateTime
```

---

### Агрегат: Медицинская карта пациента (MedicalRecord)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Управление медицинской картой пациента |
| **Aggregate Root** | `MedicalRecord` |
| **Идентификатор** | `medical_record_id: UUID` |
| **Границы** | Включает: все записи врачей, диагнозы, назначения, прикреплённые снимки. Не включает: информацию о приёмах (только ссылки). |

**Инварианты:**
- Запись в карте не может быть удалена (только аннулирована с указанием причины)
- Каждая запись должна быть подписана врачом
- Диагностические снимки должны быть привязаны к конкретной записи

**Ключевые атрибуты:**
```
medical_record_id: UUID (PK)
patient_id: UUID (FK, unique)
entries: List[MedicalRecordEntry]
  - entry_id: UUID
  - appointment_id: UUID (FK)
  - doctor_id: UUID (FK)
  - diagnosis: Text
  - prescriptions: List[Prescription]
  - created_at: DateTime
diagnostic_images: List[DiagnosticImage]
  - image_id: UUID
  - entry_id: UUID (FK)
  - file_path: String
  - image_type: Enum[xray, ct, mri, ultrasound, ecg]
  - uploaded_at: DateTime
```

---

## Финтех-услуги (Банк)

### Агрегат: Кредит (Credit)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Кредитование частных лиц и организаций |
| **Aggregate Root** | `Credit` |
| **Идентификатор** | `credit_id: UUID` |
| **Границы** | Включает: заявку, график платежей, историю платежей. Не включает: данные клиента (только ссылка). |

**Инварианты:**
- Сумма кредита не может быть отрицательной
- Процентная ставка фиксируется на момент одобрения
- Статус заявки может меняться: `pending → approved → active → closed` или `pending → rejected`
- Сумма всех платежей не может превышать сумму кредита + проценты

**Ключевые атрибуты:**
```
credit_id: UUID (PK)
applicant_id: UUID (FK)
amount: Decimal
interest_rate: Decimal
term_months: Integer
status: Enum[pending, approved, rejected, active, closed]
payment_schedule: List[ScheduledPayment]
payments: List[Payment]
created_at: DateTime
approved_at: DateTime?
```

---

### Агрегат: Исходящий счёт на оплату (Invoice)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Банковское обслуживание подразделений концерна |
| **Aggregate Root** | `Invoice` |
| **Идентификатор** | `invoice_id: UUID` |
| **Границы** | Включает: позиции счёта, статус оплаты, прикреплённые документы. Не включает: детали услуг (только ссылки). |

**Инварианты:**
- Сумма счёта равна сумме всех позиций
- После оплаты счёт не может быть изменён
- Срок оплаты не может быть в прошлом на момент создания

**Ключевые атрибуты:**
```
invoice_id: UUID (PK)
payer_id: UUID (FK)
issuer_department_id: UUID (FK)
items: List[InvoiceItem]
total_amount: Decimal
currency: String
due_date: Date
status: Enum[draft, sent, paid, overdue, cancelled]
attachments: List[Document]
created_at: DateTime
paid_at: DateTime?
```

---

### Агрегат: Платёж (Payment)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Банковское обслуживание подразделений концерна |
| **Aggregate Root** | `Payment` |
| **Идентификатор** | `payment_id: UUID` |
| **Границы** | Включает: сумму, статус, связанный счёт/кредит. Атомарная операция. |

**Инварианты:**
- Сумма платежа должна быть положительной
- Платёж не может быть отменён после проведения (только возврат как отдельная операция)

**Ключевые атрибуты:**
```
payment_id: UUID (PK)
invoice_id: UUID? (FK)
credit_id: UUID? (FK)
amount: Decimal
currency: String
status: Enum[pending, completed, failed, refunded]
payment_method: Enum[bank_transfer, card, cash]
processed_at: DateTime
```

---

## ИИ-сервисы (ИИ-компания)

### Агрегат: Заявка на анализ данных (AnalysisRequest)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Обработка входящих медицинских данных |
| **Aggregate Root** | `AnalysisRequest` |
| **Идентификатор** | `request_id: UUID` |
| **Границы** | Включает: входные данные, результаты анализа, статус. Не включает: модели ИИ, исходные снимки (только ссылки). |

**Инварианты:**
- Заявка должна содержать хотя бы один файл для анализа
- Результат может быть добавлен только после успешного выполнения
- Статус: `pending → processing → completed` или `pending → processing → failed`

**Ключевые атрибуты:**
```
request_id: UUID (PK)
partner_id: UUID (FK)
patient_reference: String (external ID)
input_files: List[InputFile]
  - file_id: UUID
  - file_type: Enum[xray, ct, mri, ecg, lab_results]
  - file_path: String
analysis_type: Enum[pathology_detection, measurement, classification]
status: Enum[pending, processing, completed, failed]
result: AnalysisResult?
  - findings: List[Finding]
  - pathologies_detected: Boolean
  - confidence_score: Decimal
  - report_path: String
created_at: DateTime
completed_at: DateTime?
```

---

## IT-сервисы (Головной офис)

### Агрегат: Infrastructure Unit

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Облачный хостинг для подразделений концерна |
| **Aggregate Root** | `InfrastructureUnit` |
| **Идентификатор** | `infra_unit_id: UUID` |
| **Границы** | Включает: terraform-конфигурацию, статус развёртывания, ресурсы. Не включает: содержимое развёрнутых сервисов. |

**Инварианты:**
- Конфигурация должна быть валидным Terraform-кодом
- Ресурсы не могут превышать квоту подразделения
- Статус: `pending → deploying → active` или `pending → deploying → failed`

**Ключевые атрибуты:**
```
infra_unit_id: UUID (PK)
department_id: UUID (FK)
git_repo_url: String
terraform_config_path: String
resource_type: Enum[vm, vm_cluster, k8s_cluster]
status: Enum[pending, deploying, active, updating, failed, destroyed]
resources: ResourceSpec
  - cpu_cores: Integer
  - memory_gb: Integer
  - storage_gb: Integer
access_keys: EncryptedBlob
created_at: DateTime
last_deployed_at: DateTime?
```

---

## Аналитика и планирование (Головной офис)

### Агрегат: Квартальный отчёт (QuarterlyReport)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Анализ эффективности подразделений |
| **Aggregate Root** | `QuarterlyReport` |
| **Идентификатор** | `report_id: UUID` |
| **Границы** | Включает: финансовые показатели, KPI подразделений, комментарии. Snapshot на момент публикации. |

**Инварианты:**
- Отчёт за один квартал может быть только один
- После публикации отчёт не может быть изменён (только версионирование)

**Ключевые атрибуты:**
```
report_id: UUID (PK)
year: Integer
quarter: Integer (1-4)
status: Enum[draft, review, published]
financial_summary: FinancialData
department_kpis: List[DepartmentKPI]
published_at: DateTime?
```

---

### Агрегат: Корпоративный бюджет (CorporateBudget)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Перспективное планирование |
| **Aggregate Root** | `CorporateBudget` |
| **Идентификатор** | `budget_id: UUID` |
| **Границы** | Включает: статьи бюджета, плановые и фактические показатели. Версионируется при изменениях. |

**Инварианты:**
- Сумма всех статей должна соответствовать общему бюджету
- Изменения бюджета требуют аудит-лога

**Ключевые атрибуты:**
```
budget_id: UUID (PK)
fiscal_year: Integer
version: Integer
status: Enum[draft, approved, active, closed]
items: List[BudgetItem]
  - item_id: UUID
  - category: String
  - department_id: UUID?
  - planned_amount: Decimal
  - actual_amount: Decimal
total_planned: Decimal
total_actual: Decimal
```

---

## Производство лекарств (Фарма)

### Агрегат: Производственный заказ (ProductionOrder)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Управление производством лекарственных препаратов |
| **Aggregate Root** | `ProductionOrder` |
| **Идентификатор** | `order_id: UUID` |
| **Границы** | Включает: спецификацию продукта, операции, расход материалов. Не включает: складские остатки. |

**Инварианты:**
- Заказ не может быть выполнен без достаточного количества материалов
- Каждая операция должна быть выполнена в правильной последовательности
- Партия готовой продукции должна пройти контроль качества

**Ключевые атрибуты:**
```
order_id: UUID (PK)
product_id: UUID (FK)
quantity: Integer
status: Enum[planned, in_progress, quality_check, completed, cancelled]
operations: List[ProductionOperation]
  - operation_id: UUID
  - operation_type: String
  - status: Enum[pending, in_progress, completed]
  - completed_at: DateTime?
material_consumption: List[MaterialUsage]
output_batch_id: UUID?
created_at: DateTime
```

---

### Агрегат: Партия материалов (MaterialBatch)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Управление производством лекарственных препаратов |
| **Aggregate Root** | `MaterialBatch` |
| **Идентификатор** | `batch_id: UUID` |
| **Границы** | Включает: количество, срок годности, статус качества. Отслеживается от поступления до списания. |

**Инварианты:**
- Количество не может быть отрицательным
- Партия с истёкшим сроком годности должна быть списана
- Расход не может превышать остаток

**Ключевые атрибуты:**
```
batch_id: UUID (PK)
material_id: UUID (FK)
quantity: Decimal
unit: String
expiry_date: Date
quality_status: Enum[pending_check, approved, rejected, expired]
supplier_id: UUID (FK)
received_at: DateTime
```

---

### Агрегат: Заказ клиента (CustomerOrder)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Управление продажами |
| **Aggregate Root** | `CustomerOrder` |
| **Идентификатор** | `order_id: UUID` |
| **Границы** | Включает: позиции заказа, статус доставки, документы. Не включает: производство. |

**Инварианты:**
- Заказ должен содержать хотя бы одну позицию
- Отгрузка возможна только при наличии товара на складе
- Статус: `pending → confirmed → shipped → delivered` или `pending → cancelled`

**Ключевые атрибуты:**
```
order_id: UUID (PK)
customer_id: UUID (FK)
items: List[OrderItem]
  - product_id: UUID
  - quantity: Integer
  - price: Decimal
total_amount: Decimal
status: Enum[pending, confirmed, processing, shipped, delivered, cancelled]
shipping_address: Address
created_at: DateTime
shipped_at: DateTime?
```

---

## Производство медицинской электроники

### Агрегат: Устройство (Device)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Сбор и обработка телеметрии |
| **Aggregate Root** | `Device` |
| **Идентификатор** | `device_id: UUID`, `serial_number: String` |
| **Границы** | Включает: серийный номер, версию ПО, владельца, историю телеметрии. Не включает: детали производства. |

**Инварианты:**
- Серийный номер уникален
- Устройство должно быть зарегистрировано перед отправкой телеметрии
- Версия ПО должна существовать в реестре

**Ключевые атрибуты:**
```
device_id: UUID (PK)
serial_number: String (unique)
model_id: UUID (FK)
owner_id: UUID (FK)
firmware_version: String
registration_date: Date
warranty_expiry_date: Date
status: Enum[active, maintenance, decommissioned]
last_telemetry_at: DateTime?
```

---

### Агрегат: Заказ на ремонт (RepairOrder)

| Характеристика | Описание |
|----------------|----------|
| **Bounded Context** | Гарантийный и негарантийный ремонт |
| **Aggregate Root** | `RepairOrder` |
| **Идентификатор** | `repair_order_id: UUID` |
| **Границы** | Включает: описание проблемы, выполненные работы, использованные запчасти. |

**Инварианты:**
- Заказ должен быть привязан к существующему устройству
- Гарантийный ремонт возможен только в пределах гарантийного срока
- Статус: `registered → diagnostics → in_repair → completed` или `registered → cancelled`

**Ключевые атрибуты:**
```
repair_order_id: UUID (PK)
device_id: UUID (FK)
customer_id: UUID (FK)
issue_description: Text
is_warranty: Boolean
status: Enum[registered, diagnostics, waiting_parts, in_repair, completed, cancelled]
diagnosis: Text?
work_performed: List[WorkItem]
parts_used: List[PartUsage]
total_cost: Decimal
created_at: DateTime
completed_at: DateTime?
```
