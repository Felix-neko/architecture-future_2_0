# Примеры доменных событий

Описание доменных событий с указанием контекста-источника, семантики и минимального контракта.

---

## Медицинские услуги (Клиники)

### AppointmentCreated

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление приёмами пациентов |
| **Агрегат** | Appointment |
| **Семантика** | Создана новая запись на приём к врачу. Триггерит процесс выставления счёта в банке. |
| **Топик Kafka** | `clinics.appointments` |

**Минимальный контракт:**
```json
{
  "event_type": "AppointmentCreated",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "appointment_id": "uuid",
    "patient_id": "uuid",
    "doctor_id": "uuid",
    "clinic_id": "uuid",
    "scheduled_at": "ISO8601",
    "service_type": "string",
    "estimated_cost": "decimal"
  }
}
```

---

### AppointmentRescheduled

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление приёмами пациентов |
| **Агрегат** | Appointment |
| **Семантика** | Запись на приём перенесена на другое время или к другому врачу. |
| **Топик Kafka** | `clinics.appointments` |

**Минимальный контракт:**
```json
{
  "event_type": "AppointmentRescheduled",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "appointment_id": "uuid",
    "previous_scheduled_at": "ISO8601",
    "new_scheduled_at": "ISO8601",
    "previous_doctor_id": "uuid",
    "new_doctor_id": "uuid",
    "reason": "string?"
  }
}
```

---

### AppointmentCancelled

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление приёмами пациентов |
| **Агрегат** | Appointment |
| **Семантика** | Запись на приём отменена. Триггерит отмену/возврат счёта в банке. |
| **Топик Kafka** | `clinics.appointments` |

**Минимальный контракт:**
```json
{
  "event_type": "AppointmentCancelled",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "appointment_id": "uuid",
    "cancelled_by": "enum[patient, clinic, doctor]",
    "reason": "string?",
    "refund_required": "boolean"
  }
}
```

---

### AppointmentCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление приёмами пациентов |
| **Агрегат** | Appointment |
| **Семантика** | Приём состоялся. Подтверждает оказание услуги. |
| **Топик Kafka** | `clinics.appointments` |

**Минимальный контракт:**
```json
{
  "event_type": "AppointmentCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "appointment_id": "uuid",
    "actual_duration_minutes": "integer",
    "services_rendered": ["string"],
    "final_cost": "decimal"
  }
}
```

---

### MedicalRecordEntryAdded

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление медицинской картой пациента |
| **Агрегат** | MedicalRecord |
| **Семантика** | Врач добавил запись в медицинскую карту пациента (диагноз, назначения). |
| **Топик Kafka** | `clinics.medical_records` |

**Минимальный контракт:**
```json
{
  "event_type": "MedicalRecordEntryAdded",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "medical_record_id": "uuid",
    "entry_id": "uuid",
    "patient_id": "uuid",
    "doctor_id": "uuid",
    "appointment_id": "uuid?",
    "entry_type": "enum[diagnosis, prescription, note, referral]"
  }
}
```

---

### DiagnosticImagesAdded

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление медицинской картой пациента |
| **Агрегат** | MedicalRecord |
| **Семантика** | Добавлены диагностические снимки (рентген, КТ, МРТ, УЗИ, ЭКГ). Триггерит автоматический ИИ-анализ. |
| **Топик Kafka** | `clinics.medical_records` |

**Минимальный контракт:**
```json
{
  "event_type": "DiagnosticImagesAdded",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "medical_record_id": "uuid",
    "patient_id": "uuid",
    "images": [
      {
        "image_id": "uuid",
        "image_type": "enum[xray, ct, mri, ultrasound, ecg]",
        "body_part": "string",
        "file_reference": "string"
      }
    ],
    "request_ai_analysis": "boolean"
  }
}
```

---

## Финтех-услуги (Банк)

### CreditApplicationCreated

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Кредитование частных лиц и организаций |
| **Агрегат** | Credit |
| **Семантика** | Подана заявка на кредит. Начинается процесс скоринга. |
| **Топик Kafka** | `bank.credits` |

**Минимальный контракт:**
```json
{
  "event_type": "CreditApplicationCreated",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "credit_id": "uuid",
    "applicant_id": "uuid",
    "applicant_type": "enum[individual, organization]",
    "requested_amount": "decimal",
    "term_months": "integer",
    "purpose": "string"
  }
}
```

---

### CreditApproved

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Кредитование частных лиц и организаций |
| **Агрегат** | Credit |
| **Семантика** | Кредит одобрен. Триггерит разблокировку записи на лечение в кредит (для клиник). |
| **Топик Kafka** | `bank.credits` |

**Минимальный контракт:**
```json
{
  "event_type": "CreditApproved",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "credit_id": "uuid",
    "applicant_id": "uuid",
    "approved_amount": "decimal",
    "interest_rate": "decimal",
    "term_months": "integer",
    "first_payment_date": "date"
  }
}
```

---

### CreditPaymentReceived

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Кредитование частных лиц и организаций |
| **Агрегат** | Credit |
| **Семантика** | Получен платёж по кредиту. |
| **Топик Kafka** | `bank.credits` |

**Минимальный контракт:**
```json
{
  "event_type": "CreditPaymentReceived",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "credit_id": "uuid",
    "payment_id": "uuid",
    "amount": "decimal",
    "remaining_balance": "decimal",
    "is_final_payment": "boolean"
  }
}
```

---

### InvoiceCreated

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Банковское обслуживание подразделений концерна |
| **Агрегат** | Invoice |
| **Семантика** | Выставлен счёт на оплату (для корпоративных клиентов или физлиц). |
| **Топик Kafka** | `bank.invoices` |

**Минимальный контракт:**
```json
{
  "event_type": "InvoiceCreated",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "invoice_id": "uuid",
    "payer_id": "uuid",
    "payer_type": "enum[individual, organization]",
    "issuer_department_id": "uuid",
    "total_amount": "decimal",
    "currency": "string",
    "due_date": "date",
    "reference_id": "uuid?",
    "reference_type": "enum[appointment, order, service]?"
  }
}
```

---

### PaymentReceived

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Банковское обслуживание подразделений концерна |
| **Агрегат** | Payment |
| **Семантика** | Получена оплата по счёту. Триггерит уведомление подразделения-получателя. |
| **Топик Kafka** | `bank.payments` |

**Минимальный контракт:**
```json
{
  "event_type": "PaymentReceived",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "payment_id": "uuid",
    "invoice_id": "uuid",
    "payer_id": "uuid",
    "amount": "decimal",
    "payment_method": "enum[bank_transfer, card, cash]",
    "beneficiary_department_id": "uuid"
  }
}
```

---

### PaymentProcessed

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Банковское обслуживание подразделений концерна |
| **Агрегат** | Payment |
| **Семантика** | Исходящий платёж проведён. |
| **Топик Kafka** | `bank.payments` |

**Минимальный контракт:**
```json
{
  "event_type": "PaymentProcessed",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "payment_id": "uuid",
    "from_account_id": "uuid",
    "to_account_id": "uuid",
    "amount": "decimal",
    "currency": "string",
    "reference": "string?"
  }
}
```

---

## ИИ-сервисы (ИИ-компания)

### AnalysisRequestReceived

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Обработка входящих медицинских данных |
| **Агрегат** | AnalysisRequest |
| **Семантика** | Поступила заявка на ИИ-анализ медицинских данных. |
| **Топик Kafka** | `ai.analysis_requests` |

**Минимальный контракт:**
```json
{
  "event_type": "AnalysisRequestReceived",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "request_id": "uuid",
    "partner_id": "uuid",
    "patient_reference": "string",
    "analysis_type": "enum[pathology_detection, measurement, classification]",
    "file_count": "integer",
    "priority": "enum[normal, urgent]"
  }
}
```

---

### AnalysisCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Обработка входящих медицинских данных |
| **Агрегат** | AnalysisRequest |
| **Семантика** | ИИ-анализ успешно завершён. Триггерит обновление медицинской карты в клинике. |
| **Топик Kafka** | `ai.analysis_requests` |

**Минимальный контракт:**
```json
{
  "event_type": "AnalysisCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "request_id": "uuid",
    "partner_id": "uuid",
    "patient_reference": "string",
    "processing_time_ms": "integer",
    "result_summary": "string",
    "report_url": "string"
  }
}
```

---

### PathologyDetected

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Обработка входящих медицинских данных |
| **Агрегат** | AnalysisRequest |
| **Семантика** | Обнаружена патология. Триггерит срочное уведомление врача. **Критичное событие.** |
| **Топик Kafka** | `ai.alerts` |

**Минимальный контракт:**
```json
{
  "event_type": "PathologyDetected",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "request_id": "uuid",
    "partner_id": "uuid",
    "patient_reference": "string",
    "pathology_type": "string",
    "severity": "enum[low, medium, high, critical]",
    "confidence_score": "decimal",
    "affected_area": "string",
    "recommendation": "string"
  }
}
```

---

## IT-сервисы (Головной офис)

### InfraDeploymentRequested

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Облачный хостинг для подразделений концерна |
| **Агрегат** | InfrastructureUnit |
| **Семантика** | Получена заявка на развёртывание инфраструктуры (через коммит в Git). |
| **Топик Kafka** | `platform.infrastructure` |

**Минимальный контракт:**
```json
{
  "event_type": "InfraDeploymentRequested",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "infra_unit_id": "uuid",
    "department_id": "uuid",
    "git_commit_sha": "string",
    "resource_type": "enum[vm, vm_cluster, k8s_cluster]",
    "requested_resources": {
      "cpu_cores": "integer",
      "memory_gb": "integer",
      "storage_gb": "integer"
    }
  }
}
```

---

### InfraDeploymentCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Облачный хостинг для подразделений концерна |
| **Агрегат** | InfrastructureUnit |
| **Семантика** | Инфраструктура успешно развёрнута. Отправляются ключи доступа. |
| **Топик Kafka** | `platform.infrastructure` |

**Минимальный контракт:**
```json
{
  "event_type": "InfraDeploymentCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "infra_unit_id": "uuid",
    "department_id": "uuid",
    "deployed_resources": {
      "endpoints": ["string"],
      "ip_addresses": ["string"]
    },
    "deployment_time_seconds": "integer"
  }
}
```

---

### InfraDeploymentFailed

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Облачный хостинг для подразделений концерна |
| **Агрегат** | InfrastructureUnit |
| **Семантика** | Развёртывание завершилось ошибкой. Требуется вмешательство. |
| **Топик Kafka** | `platform.infrastructure` |

**Минимальный контракт:**
```json
{
  "event_type": "InfraDeploymentFailed",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "infra_unit_id": "uuid",
    "department_id": "uuid",
    "error_code": "string",
    "error_message": "string",
    "terraform_output": "string?"
  }
}
```

---

### ETLProcessCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Платформа данных для подразделений концерна |
| **Агрегат** | — (системное событие) |
| **Семантика** | ETL-процесс завершён. Триггерит обновление аналитических витрин. |
| **Топик Kafka** | `platform.etl` |

**Минимальный контракт:**
```json
{
  "event_type": "ETLProcessCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "job_id": "uuid",
    "job_name": "string",
    "source_systems": ["string"],
    "target_tables": ["string"],
    "records_processed": "integer",
    "duration_seconds": "integer"
  }
}
```

---

### DataPublished

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Платформа данных для подразделений концерна |
| **Агрегат** | — (системное событие) |
| **Семантика** | Новые данные опубликованы в каталоге данных и доступны для использования. |
| **Топик Kafka** | `platform.data_catalog` |

**Минимальный контракт:**
```json
{
  "event_type": "DataPublished",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "dataset_id": "uuid",
    "dataset_name": "string",
    "schema_version": "string",
    "location": "string",
    "owner_department_id": "uuid",
    "access_level": "enum[public, restricted, confidential]"
  }
}
```

---

## Аналитика и планирование (Головной офис)

### QuarterlyReportPublished

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Анализ эффективности подразделений |
| **Агрегат** | QuarterlyReport |
| **Семантика** | Квартальный отчёт для акционеров опубликован. |
| **Топик Kafka** | `analytics.reports` |

**Минимальный контракт:**
```json
{
  "event_type": "QuarterlyReportPublished",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "report_id": "uuid",
    "year": "integer",
    "quarter": "integer",
    "report_url": "string",
    "highlights": ["string"]
  }
}
```

---

### BudgetItemChanged

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Перспективное планирование |
| **Агрегат** | CorporateBudget |
| **Семантика** | Изменена статья корпоративного бюджета. |
| **Топик Kafka** | `analytics.budget` |

**Минимальный контракт:**
```json
{
  "event_type": "BudgetItemChanged",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "budget_id": "uuid",
    "item_id": "uuid",
    "fiscal_year": "integer",
    "category": "string",
    "previous_amount": "decimal",
    "new_amount": "decimal",
    "change_reason": "string",
    "approved_by": "uuid"
  }
}
```

---

## Производство лекарств (Фарма)

### ProductionOrderCreated

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление производством лекарственных препаратов |
| **Агрегат** | ProductionOrder |
| **Семантика** | Создан заказ на производство партии лекарств. |
| **Топик Kafka** | `pharma.production` |

**Минимальный контракт:**
```json
{
  "event_type": "ProductionOrderCreated",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "order_id": "uuid",
    "product_id": "uuid",
    "product_name": "string",
    "quantity": "integer",
    "planned_start_date": "date",
    "planned_end_date": "date"
  }
}
```

---

### ProductionCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление производством лекарственных препаратов |
| **Агрегат** | ProductionOrder |
| **Семантика** | Производство завершено, партия готова к отгрузке. |
| **Топик Kafka** | `pharma.production` |

**Минимальный контракт:**
```json
{
  "event_type": "ProductionCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "order_id": "uuid",
    "output_batch_id": "uuid",
    "actual_quantity": "integer",
    "quality_status": "enum[approved, rejected]",
    "expiry_date": "date"
  }
}
```

---

### MaterialReceived

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление производством лекарственных препаратов |
| **Агрегат** | MaterialBatch |
| **Семантика** | Получена партия ТМЦ от поставщика. Триггерит проверку запасов. |
| **Топик Kafka** | `pharma.inventory` |

**Минимальный контракт:**
```json
{
  "event_type": "MaterialReceived",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "batch_id": "uuid",
    "material_id": "uuid",
    "material_name": "string",
    "quantity": "decimal",
    "unit": "string",
    "supplier_id": "uuid",
    "expiry_date": "date"
  }
}
```

---

### OrderShipped

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление продажами |
| **Агрегат** | CustomerOrder |
| **Семантика** | Заказ клиента отгружен. Триггерит расчёты в банке. |
| **Топик Kafka** | `pharma.sales` |

**Минимальный контракт:**
```json
{
  "event_type": "OrderShipped",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "order_id": "uuid",
    "customer_id": "uuid",
    "shipped_items": [
      {
        "product_id": "uuid",
        "batch_id": "uuid",
        "quantity": "integer"
      }
    ],
    "tracking_number": "string",
    "carrier": "string",
    "invoice_id": "uuid"
  }
}
```

---

## Производство медицинской электроники

### TelemetryReceived

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Сбор и обработка телеметрии |
| **Агрегат** | Device |
| **Семантика** | Получена телеметрия с устройства. Используется для анализа и прогнозирования. |
| **Топик Kafka** | `electronics.telemetry` |

**Минимальный контракт:**
```json
{
  "event_type": "TelemetryReceived",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "device_id": "uuid",
    "serial_number": "string",
    "model_id": "uuid",
    "firmware_version": "string",
    "metrics": {
      "temperature": "decimal?",
      "vibration": "decimal?",
      "operating_hours": "integer?",
      "error_codes": ["string"]
    },
    "owner_id": "uuid"
  }
}
```

---

### FailurePredicted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Сбор и обработка телеметрии |
| **Агрегат** | Device |
| **Семантика** | ИИ-модель предсказала вероятную неисправность. Триггерит проактивное уведомление клиента. |
| **Топик Kafka** | `electronics.alerts` |

**Минимальный контракт:**
```json
{
  "event_type": "FailurePredicted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "device_id": "uuid",
    "serial_number": "string",
    "owner_id": "uuid",
    "predicted_failure_type": "string",
    "probability": "decimal",
    "estimated_days_to_failure": "integer",
    "recommended_action": "string"
  }
}
```

---

### RepairOrderRegistered

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Гарантийный и негарантийный ремонт |
| **Агрегат** | RepairOrder |
| **Семантика** | Зарегистрирован заказ на ремонт устройства. |
| **Топик Kafka** | `electronics.repairs` |

**Минимальный контракт:**
```json
{
  "event_type": "RepairOrderRegistered",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "repair_order_id": "uuid",
    "device_id": "uuid",
    "serial_number": "string",
    "customer_id": "uuid",
    "issue_description": "string",
    "is_warranty": "boolean"
  }
}
```

---

### RepairCompleted

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Гарантийный и негарантийный ремонт |
| **Агрегат** | RepairOrder |
| **Семантика** | Ремонт завершён. Устройство готово к выдаче клиенту. |
| **Топик Kafka** | `electronics.repairs` |

**Минимальный контракт:**
```json
{
  "event_type": "RepairCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "repair_order_id": "uuid",
    "device_id": "uuid",
    "diagnosis": "string",
    "work_performed": ["string"],
    "parts_replaced": ["string"],
    "total_cost": "decimal",
    "warranty_applied": "boolean"
  }
}
```

---

### ProductionCompleted (Electronics)

| Характеристика | Значение |
|----------------|----------|
| **Контекст-источник** | Управление производством электроники |
| **Агрегат** | ProductionOrder |
| **Семантика** | Производство партии электроники завершено. |
| **Топик Kafka** | `electronics.production` |

**Минимальный контракт:**
```json
{
  "event_type": "ElectronicsProductionCompleted",
  "event_id": "uuid",
  "timestamp": "ISO8601",
  "payload": {
    "order_id": "uuid",
    "model_id": "uuid",
    "quantity_produced": "integer",
    "serial_numbers": ["string"],
    "quality_status": "enum[approved, rejected]"
  }
}
```
