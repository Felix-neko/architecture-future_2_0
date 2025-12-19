<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Я читаю учебное задание:

```
В этом спринте вы будете работать над кейсом компании «Будущее 2.0».
Компания «Будущее 2.0» начинала как медицинский стартап, а со временем выросла в успешный бизнес. Сегодня её врачи используют современное оборудование и системы искусственного интеллекта для постановки диагнозов и назначения лечения. А недавно компания купила банк, чтобы дополнить свои медицинские услуги финансовыми сервисами. В ближайших планах — интегрировать в экосистему нескольких фармацевтических компаний и производителя электроники для медицинского оборудования.  
Изначально все корпоративные данные в «Будущем 2.0» хранились в DWH, построенном на базе SQL Server. В нём была реализована значительная часть бизнес-логики, а для работы операторов в клиниках использовался интерфейс на PowerBuilder.
В DWH лежат:
Данные по клиентам.
Медицинские карты и истории болезни, в том числе данные исследований, включая результаты диагностических исследований, проведённых в ходе лечения.
Финансовая история.
Счета.
Данные о кредитах.
Данные по персоналу больницы.
Данные по инвентаризации.
Финансовая отчётность и много другой информации.
«Будущее 2.0» хочет развивать каждое из своих направлений отдельно, сохраняя при этом целостное представление по ключевым бизнес-показателям. Однако уже сейчас построение необходимой отчётности занимает слишком много времени. Объём данных измеряется сотнями терабайт, а сценариев их использования — невероятное множество, что приводит к большому количеству трансформаций. В результате замедляется time-to-market и падает производительность аналитических процессов: формирование сложных отчётов может занимать часы.
```

Реально ли напихать сотни терабайт в DWH на Microsoft SQL Server? Или здесь забыли указать какое-то файлохранилище, которое и берёт на себя основной объём?

Ваши сомнения абсолютно обоснованы. Короткий ответ: **технически это возможно, но на практике — это архитектурный кошмар**, который в описании кейса, скорее всего, приведён специально как «проблемная точка» (pain point), которую вам предстоит решать.

Вот детальный разбор ситуации, почему ваша интуиция вас не подводит.

### 1. Теоретические лимиты SQL Server

Microsoft SQL Server действительно позволяет создавать базы данных колоссальных размеров.

* **Максимальный размер базы данных:** 524 272 терабайта (512 петабайт).[^1_1]
* **Максимальный размер одного файла данных:** 16 терабайт. Чтобы хранить сотни терабайт, администраторам пришлось бы создавать десятки файлов данных (`.ndf`), разнесенных по разным дисковым массивам.

Так что формально «напихать» туда сотни терабайт можно. Программа не выдаст ошибку "место кончилось", пока есть место на дисках.

### 2. Почему это «архитектурный ад»

Хранение медицинских данных (снимки МРТ, КТ, рентген — это файлы формата DICOM, которые весят очень много) непосредственно внутри реляционной базы данных (в полях типа `VARBINARY(MAX)`) считается антипаттерном для таких объемов.[^1_2][^1_3]

* **Резервное копирование и восстановление:** Сделать бэкап базы в 500 ТБ — это задача, занимающая дни или недели. В случае сбоя бизнес встанет на недопустимо долгое время. Восстановление (Restore) такой базы практически нереализуемо в разумные сроки (RTO).
* **Производительность:** Буферный пул (оперативная память) SQL Server будет "засоряться" страницами с бинарными данными, вытесняя полезные для аналитики индексы и табличные данные. Это одна из причин, почему в кейсе сказано: «формирование сложных отчётов может занимать часы».
* **Стоимость:** Дисковое пространство на высокопроизводительных массивах (SAN), необходимых для SQL Server, стоит в разы дороже, чем обычное объектное хранилище (S3) или файловые серверы.


### 3. Где "спрятано" файлохранилище?

Скорее всего, в кейсе подразумевается один из двух сценариев:

**Сценарий А: Использование FILESTREAM**
В SQL Server есть технология **FILESTREAM**. Она позволяет хранить бинарные данные (файлы) в файловой системе NTFS, но управлять ими через SQL Server как обычными колонками.[^1_4]

* Для разработчика и пользователя это выглядит как «всё лежит в SQL Server».
* Физически файлы лежат в папке на диске, минуя основной движок базы данных, но сохраняя транзакционную целостность.
* Даже с FILESTREAM сотни терабайт делают администрирование очень сложным.

**Сценарий Б: Это и есть суть проблемы**
Вы читаете учебный кейс. Часто в таких заданиях специально описывают **Legacy-систему с плохой архитектурой** («монолит»).
Фраза «*Изначально все данные... хранились в DWH на SQL Server*» и упоминание проблем с производительностью («*замедляется time-to-market*») прямо намекают на то, что текущая архитектура не справляется.

### Резюме

Вы правы: в реальном современном проекте «Будущее 2.0» снимки и неструктурированные данные лежали бы в **Data Lake** (Hadoop/S3/Azure Blob) или **PACS-системе** (для медицины), а DWH хранил бы только ссылки на них и текстовые метаданные.

В данном кейсе "сотня терабайт в SQL Server" — это, скорее всего, **диагноз**, который вы как аналитик/архитектор должны поставить текущей системе, чтобы обосновать необходимость миграции на современный стек (Data Lake + DWH).
<span style="display:none">[^1_10][^1_11][^1_12][^1_13][^1_14][^1_15][^1_16][^1_17][^1_18][^1_19][^1_20][^1_21][^1_22][^1_23][^1_24][^1_25][^1_26][^1_27][^1_28][^1_29][^1_30][^1_31][^1_32][^1_33][^1_34][^1_35][^1_36][^1_37][^1_38][^1_39][^1_40][^1_41][^1_42][^1_43][^1_44][^1_5][^1_6][^1_7][^1_8][^1_9]</span>

<div align="center">⁂</div>

[^1_1]: https://ora.it.com/sql-server-limits/what-are-the-maximum-size-limits-in-sql-server/

[^1_2]: https://www.brentozar.com/archive/2021/07/store-files-in-a-file-system-not-a-relational-database/

[^1_3]: https://joeydantoni.com/2024/10/17/storing-files-in-your-databases-why-you-shouldnt-and-what-you-should-do-instead/

[^1_4]: https://www.reddit.com/r/csharp/comments/b268ws/saving_file_in_filesystem_vs_as_blob_in_database/

[^1_5]: http://dergipark.org.tr/tr/doi/10.46460/ijiea.1070325

[^1_6]: https://www.semanticscholar.org/paper/033c9a5b3aff5bc508db182dcfb5f3de4f5b59b4

[^1_7]: https://www.semanticscholar.org/paper/b1ff4b0ebb42244b2652f972d94c2cfd37d8b1fc

[^1_8]: https://www.semanticscholar.org/paper/99a5fb5a9ce146509d10e6ee80c3d8cd60029605

[^1_9]: https://ieeexplore.ieee.org/document/9537400/

[^1_10]: http://koreascience.or.kr/journal/view.jsp?kj=JBBHCB\&py=2017\&vnc=v27n2\&sp=223

[^1_11]: https://ieeexplore.ieee.org/document/9328241/

[^1_12]: https://dl.acm.org/doi/10.14778/2536222.2536248

[^1_13]: http://dl.acm.org/citation.cfm?doid=2790798.2790808

[^1_14]: https://dl.acm.org/doi/10.1145/1066157.1066179

[^1_15]: https://arxiv.org/pdf/2305.03111.pdf

[^1_16]: https://arxiv.org/abs/2503.02240

[^1_17]: https://arxiv.org/pdf/2312.00638.pdf

[^1_18]: http://arxiv.org/pdf/1711.03860.pdf

[^1_19]: http://arxiv.org/pdf/1501.02549.pdf

[^1_20]: https://arxiv.org/pdf/2209.06977.pdf

[^1_21]: http://arxiv.org/pdf/1203.0056.pdf

[^1_22]: https://arxiv.org/pdf/2306.00739.pdf

[^1_23]: https://learn.microsoft.com/en-us/answers/questions/315117/sql-server-express-database-size-limit-total-or-us

[^1_24]: https://www.reddit.com/r/AZURE/comments/11s07nb/beginner_question_the_database_size_limit_is_4tb/

[^1_25]: https://manage.accuwebhosting.com/knowledgebase/3769/How-to-set-database-size-limit-on-MSSQL-Server.html

[^1_26]: https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?view=sql-server-ver17

[^1_27]: https://bizacuity.com/case-studies/enterprise-data-warehouse-migration-from-sql-server-to-snowflake/

[^1_28]: https://asktopia.com/question/8WnUfdrRQ8GQaulGixUzNA/what-are-the-pros-and-cons-of-storing-files-directly-in-a-sql-server-database

[^1_29]: https://support.gfi.com/article/109384-size-limitation-database-size-for-microsoft-sql-server-versions-from-2000-to-2016

[^1_30]: https://www.dwconsultants.com/sqldatawarehousereview/

[^1_31]: https://www.sqlservercentral.com/forums/topic/file-system-vs-blob

[^1_32]: https://www.sqlservercentral.com/forums/topic/database-size-in-sql-server-2012/page/2

[^1_33]: https://www.microsoft.com/en-us/sql-server/blog/2016/07/12/the-elastic-future-of-data-warehousing/

[^1_34]: https://stackoverflow.com/questions/1124374/store-files-in-sql-server-or-keep-them-on-the-file-server

[^1_35]: https://stackoverflow.com/questions/51614936/is-there-a-limit-size-for-a-sql-server-database/51614960

[^1_36]: https://www.delltechnologies.com/asset/en-us/products/servers/industry-market/100tb-scv-sql-dwft-ra-dell-emc-ra-sql.pdf

[^1_37]: https://stackoverflow.com/questions/15151901/what-is-the-maximum-capacity-of-databases-in-microsoft-sql-server-2005-and-2008

[^1_38]: https://www.slideshare.net/slideshow/scaling-sql-server-to-hundreds-of-terabytes/16065882

[^1_39]: https://www.reddit.com/r/SQLServer/comments/14yea4x/microsoft_sql_10_gb_limit/

[^1_40]: https://www.databricks.com/blog/2021/11/02/databricks-sets-official-data-warehousing-performance-record.html

[^1_41]: https://lenovopress.lenovo.com/sb0007.pdf

[^1_42]: https://www.facebook.com/groups/programadorespuertorico/posts/549416818552717/

[^1_43]: https://download.microsoft.com/download/C/2/D/C2D2D5FA-768A-49AD-8957-1A434C6C8126/Microsoft_Modern_Data_Warehouse_white_paper.pdf

[^1_44]: https://download.microsoft.com/download/8/D/2/8D2D7181-6CF9-4C0D-BEC2-225DE5A4310F/Introducing_Microsoft_Data_Warehouse_Fast_Track_for_SQL_Server_2016_EN_US.pdf


---

# Я хочу построить современное хранилище данных типа Data LakeHouse.

1) Первичное сохранение сырых данных (в т.ч. неструктурированных) в S3-хранилище, коэффициент избыточности 2;
2) ELT-процессы с использованием PySpark + Apache Iceberg поверх S3.
3) Возможно -- горячее хранилище на ScyllaDB, если нам понадобится запускать модели с низкой латентностью.

Объём данных в хранилище ожидается достаточно большим, в районе 1 петабайта.
Объём данных, единовременно извлекаемых в память с помощью PySpark, будет ниже, не более 5 Тб.

Набросай мне ориентировочную конфигурацию дата-центра, который мне понадобится, чтобы хранить и обрабатывать такие объёмы данных?
Верно ли я понимаю, что для minio-кластера мне нужны ноды одного класса, а для Spark-кластера -- ноды другого класса?

Это отличный, современный подход. Архитектура с разделением слоёв хранения и вычислений (**Storage-Compute Separation**) — это индустриальный стандарт для таких объёмов в 2025 году.

Отвечая на ваш второй вопрос сразу: **Да, вы абсолютно правы.** Для MinIO и Spark вам нужны принципиально разные конфигурации серверов (hardware profiles). Пытаться делать гиперконвергентную систему (где одни и те же ноды и хранят, и считают) на объёмах в 1 ПБ — это путь к проблемам с утилизацией ресурсов («stranding resources»).

Ниже приведена ориентировочная конфигурация дата-центра (или стойки) для вашего кейса.

***

### 1. Storage-кластер (S3 / MinIO)

**Задача:** Хранить 1 ПБ полезных данных.
**Условие:** Коэффициент избыточности 2 (в MinIO это реализуется через **Erasure Coding**, что эффективнее простого зеркалирования, но для расчёта ёмкости (Raw Capacity) примем, что нам нужно **2 ПБ физического места** + запас на overhead файловой системы и метаданных ~20%).
**Итого Raw Capacity:** ~2.4–2.5 ПБ.

**Профиль оборудования: High Density Storage**
Здесь важна плотность дисков и пропускная способность сети, CPU вторичен.

* **Количество нод:** 8–10 серверов.
* **Диски (HDD):** Используем современные Nearline SAS/SATA диски объёмом 20–22 ТБ.
    * На одну ноду: 16 дисков по 20 ТБ = 320 ТБ/нода.
    * 8 нод × 320 ТБ = 2.56 ПБ.
* **Кэш/Метаданные (NVMe):** 2 x 3.84 ТБ NVMe (MinIO активно использует быстрые диски для метаданных и тиринга горячих данных).
* **RAM:** 128 ГБ (MinIO любит кэшировать в RAM).
* **Сеть:** 2 x 25 GbE (минимум) или 2 x 100 GbE (рекомендуется для 2025 года при таких объёмах, чтобы не было бутылочного горлышка при фул-сканах Spark).

***

### 2. Compute-кластер (PySpark + Iceberg)

**Задача:** Поднимать в память до 5 ТБ данных для трансформаций.
**Нюанс:** Spark требует памяти не только под сами данные, но и под JVM Heap overhead, Execution memory и Storage memory. Чтобы комфортно крутить 5 ТБ *полезных* данных в памяти без постоянного (и медленного) сброса на диск (Spill to Disk), вам нужно суммарно около **8–10 ТБ RAM** в кластере.

**Профиль оборудования: Memory Optimized / Compute Intensive**
Здесь важны ядра CPU, много быстрой RAM и очень быстрый *локальный* диск для временных файлов (Shuffle).

* **Количество нод:** 10–12 серверов.
* **CPU:** Dual Socket (AMD EPYC или Intel Xeon Gold/Platinum), суммарно 64–96 физических ядер на ноду.
* **RAM:** 768 ГБ или 1 ТБ DDR5 на ноду.
    * 10 нод × 1 ТБ = 10 ТБ RAM (идеально для вашей задачи).
* **Локальный диск (Scratch/Shuffle):** Это критически важно! 2 x 3.84 ТБ NVMe (RAID 0 или JBOD).
    * *Почему:* Когда данные не влезут в RAM (а при джойнах больших таблиц это случится), Spark начнет писать "shuffle files" на диск. Если это будет HDD, процесс встанет. Нужны локальные NVMe.
* **Сеть:** 2 x 25 GbE. Здесь трафик в основном "горизонтальный" (shuffle между нодами).

***

### 3. Hot Layer (ScyllaDB) — Опционально

Если нужна real-time отдача фич для ML или быстрые лукапы. ScyllaDB работает по архитектуре "Shard per Core" и требует очень быстрого I/O.

**Профиль оборудования: High Performance NVMe**

* **Количество нод:** Минимум 3 (для кворума).
* **Диски:** Только NVMe (SATA SSD будут узким местом). 4–8 x NVMe дисков.
* **CPU:** Высокая частота важна.
* **RAM:** 256–512 ГБ.

***

### 4. Сетевая инфраструктура (The Backbone)

При разделении Storage и Compute сеть становится главным компонентом. Spark будет вычитывать терабайты данных с MinIO по сети.

* **Архитектура:** Spine-Leaf (CLOS).
* **Коммутаторы (ToR - Top of Rack):** Вам понадобятся 100GbE свитчи.
    * Минимум 2 свитча для отказоустойчивости (MLAG/VPC).
* **Пропускная способность:** Учитывая, что вы хотите читать 5 ТБ данных, на скорости 10 Гбит/с это займет больше часа. На скорости 100 Гбит/с — около 7-10 минут. Для Data Lakehouse 2025 года стандартом де-факто является 25GbE до сервера и 100GbE на аплинках.

***

### Итоговая таблица (Bill of Materials draft)

| Роль | Кол-во нод | CPU (Cores) | RAM | Storage (Data) | Storage (System/Cache) | Network |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| **MinIO (Storage)** | 8 | 32-48 | 128 GB | 16x 20TB HDD | 2x 4TB NVMe | 2x 100GbE |
| **Spark (Compute)** | 10 | 64-96 | 1 TB | - | 2x 4TB NVMe (Shuffle) | 2x 25GbE |
| **Scylla (Hot)** | 3 | 32-64 | 256 GB | 4x 4TB NVMe | - | 2x 25GbE |

**Почему это сработает:**

1. **Масштабируемость:** Если кончится место — докупаете дешевые Storage-ноды. Если тормозят расчеты — докупаете дорогие Compute-ноды.
2. **Iceberg:** Отлично работает с S3 (MinIO), обеспечивая ACID-транзакции и Time Travel, не нагружая лишний раз файловую систему листингом файлов.
3. **Shuffle:** Выделенные NVMe на спарк-нодах спасут вас от "тормозов" при тяжелых джойнах, когда 5 ТБ RAM не хватит.

---

# Насоветуй под это конкретного железа из доступного в российских магазинах. Рассчитай ориентировочную стоимость.

Ниже приведён ориентировочный расчет («смета верхнего уровня») на железе, доступном в РФ по каналам параллельного импорта или от локальных вендоров (Depo, Aquarius, Yadro, или ребрендированный Supermicro) по ценам конца 2025 года.

> **Важно:** Цены указаны для B2B рынка с НДС. Финальная стоимость сильно зависит от курса рубля и конкретного интегратора.

### 1. Storage-узел (MinIO) — 8 штук

Нам нужны "тормозные", но очень ёмкие сервера. Идеальный кандидат — шасси 2U на 12-16 дисков LFF.

* **Платформа:** Supermicro 6029U/AS-2024 (или аналог от Yadro/Aquarius) 2U 12xLFF.
    * *Цена базы (CPU Silver/AMD EPYC + Chassis + PSU):* ~400 000 ₽
* **CPU:** 1 x AMD EPYC 7003/9004 (24 cores) или Intel Xeon Silver. Для MinIO CPU не критичен, берем средний.
    * *Входит в базу или +100 000 ₽*
* **RAM:** 128 ГБ DDR4/DDR5 ECC REG (2 x 64GB).
    * *Цена:* ~15 000 ₽ × 2 = 30 000 ₽
* **Диски (Data):** 12 x 20–22 TB HDD Enterprise (WD Gold / Seagate Exos).
    * *Цена:* ~50 000 ₽ × 12 = 600 000 ₽
* **Диски (Cache/System):** 2 x 3.84 TB NVMe Enterprise (Micron 7450 / Samsung PM9A3).
    * *Цена:* ~60 000 ₽ × 2 = 120 000 ₽
* **Сеть:** 1 x 100GbE Mellanox ConnectX-6 (или аналог).
    * *Цена:* ~100 000 ₽

**Итого за 1 узел:** ~1 250 000 ₽
**Итого за кластер (8 шт.):** ~10 000 000 ₽

***

### 2. Compute-узел (Spark) — 10 штук

Здесь деньги уходят в оперативную память и быстрые NVMe для шаффла.

* **Платформа:** 1U/2U High Density Compute (Dual Socket).
    * *Цена базы:* ~500 000 ₽
* **CPU:** 2 x Intel Xeon Gold 6xxx или AMD EPYC 9xxx (суммарно 64+ ядра).
    * *Цена:* ~300 000 ₽ за пару (б/у или OEM) или ~800 000 ₽ за новые. Считаем новые: ~800 000 ₽.
* **RAM:** 1 ТБ (16 x 64GB DDR5 ECC REG).
    * *Цена:* ~15 000 ₽ × 16 = 240 000 ₽
* **Диски (Shuffle/System):** 2 x 3.84 TB NVMe (Read Intensive).
    * *Цена:* ~60 000 ₽ × 2 = 120 000 ₽
* **Сеть:** 1 x 25GbE Dual Port (Mellanox ConnectX-4/5/6 Lx).
    * *Цена:* ~40 000 ₽

**Итого за 1 узел:** ~1 700 000 ₽
**Итого за кластер (10 шт.):** ~17 000 000 ₽

***

### 3. Сеть (Network Backbone)

Критически важная часть. Не экономьте здесь.

* **Коммутаторы:** 2 x 100GbE Switch (32 порта).
    * *Варианты:* Mellanox SN2700/SN3700 (дорого, надежно), Huawei CloudEngine 6800 серия, Eltex MES5500-32 (Россия, ~1.5 млн ₽).
    * *Цена:* ~1 500 000 ₽ × 2 = 3 000 000 ₽
* **Кабели (DAC/Optics):** На 100G оптику и DAC кабели уйдет немало.
    * *Цена:* ~500 000 ₽ (грубо).

**Итого сеть:** ~3 500 000 ₽

***

### Финальная сводка (Ориентировочно)

| Система | Стоимость (RUB) | Комментарий |
| :-- | :-- | :-- |
| **Storage (MinIO)** | 10.0 млн | 2.5 ПБ сырой ёмкости, быстрый NVMe кэш. |
| **Compute (Spark)** | 17.0 млн | 10 ТБ RAM суммарно, 640+ ядер CPU. |
| **Network** | 3.5 млн | 2x100G свитча, отказоустойчивое ядро. |
| **Стойка + ИБП** | 1.5 млн | Не забудьте про питание (~15-20 кВт) и охлаждение. |
| **Всего** | **~32 000 000 ₽** | **±20% в зависимости от вендора** |

### Рекомендации по закупке в РФ (2025)

1. **Диски (HDD/SSD):** Самая ликвидная часть. Брать **WD Gold / Ultrastar** или **Seagate Exos**. Они доступны везде (Ozon, X-Com, Regard, Servermall). Не берите SAS HDD для MinIO — переплата за контроллер не стоит того, SATA вполне достаточно.
2. **Платформы:**
    * *Бюджетно:* Китайские платформы (Gooxi, xFusion) или восстановленные (Refurbished) Dell/HPE прошлых поколений (Gen14/Gen15) с гарантией от поставщика (Servermall, Westcomp). Для MinIO б/у сервера — отличный вариант сэкономить 30-40%.
    * *Официально/Госсектор:* **Yadro**, **Aquarius**, **Fplus**. Ценник будет выше на 30-50%, сроки поставки — от 8 недель.
3. **Память:** Samsung/Hynix/Micron. Сейчас рынок наводнен китайскими брендами (KingSpec и т.д.) — для продакшна лучше избегать, берите OEM Samsung.
4. **Сеть:** **Eltex** (Новосибирск) делает отличные 100G коммутаторы (MES5500), которые реально купить официально с поддержкой. Для 25G карт в сервера — **Mellanox** (NVIDIA) всё ещё стандарт, их много на рынке.
<span style="display:none">[^3_1][^3_10][^3_11][^3_12][^3_13][^3_14][^3_15][^3_16][^3_17][^3_18][^3_19][^3_2][^3_20][^3_21][^3_22][^3_23][^3_24][^3_25][^3_26][^3_27][^3_28][^3_29][^3_3][^3_30][^3_31][^3_32][^3_33][^3_34][^3_35][^3_36][^3_37][^3_38][^3_39][^3_4][^3_40][^3_41][^3_42][^3_5][^3_6][^3_7][^3_8][^3_9]</span>

<div align="center">⁂</div>

[^3_1]: https://servermall.ru/sets/servery-s-16-diskami/

[^3_2]: https://техключи.рф/catalog/servernoe-oborudovanie/keeping_1-sistemnyy-disk-lff-sata-vozmozhnost-ustanovki-do-2-diskov-lff-sata-16-otsekov-dlya-sff-sata-sas-di/

[^3_3]: https://www.nav-it.ru/services/system-integration/sistemy-khraneniya-dannykh/price-skhd/

[^3_4]: https://www.team.ru/storage/infortrend-storage.php

[^3_5]: https://dell-servers.ru/catalog/sistemy-hraneniya-dannyh-shd/

[^3_6]: https://hostkey.ru/dedicated-servers/1tb/

[^3_7]: https://www.regard.ru/reciept/30948123/servernye-zestkie-diski-hdd-22-tb

[^3_8]: https://www.regard.ru/reciept/434196/servernye-ssd-nakopiteli-384-tb

[^3_9]: https://k-integration.ru/product/kommutator-mellanox-technologies-msn2201-cb2fc-spectrum-based-1gbase-t-100gbe-1u-open-ethernet-switch-with-cumulus-linux-48-rj45-ports-and-4-qsfp28-p/

[^3_10]: https://www.stss.ru/products/storage_san/stss_datstor/

[^3_11]: https://servermall.ru/sets/servery-s-1-tb-ram/

[^3_12]: https://www.ozon.ru/product/western-digital-22-tb-vnutrenniy-zhestkiy-disk-wd221kryz-924960530/

[^3_13]: https://shop.nav-it.ru/catalogue/servernye_zhestkie_diski_ssd/micron_7450_pro_3_84tb_nvme_u_3_15mm_ssd_enterprise_solid_state_drive_1_year_oem/

[^3_14]: https://shop.nav-it.ru/catalogue/kommutatory_1/kommutator_mellanox_spectrum_2_based_100gbe_1u_open_ethernet_switch_with_cumulus_linux_32_qsfp28_por/

[^3_15]: https://servermall.ru/sets/servery-dell-poweredge-g16/

[^3_16]: https://serverflow.ru/catalog/ai-servers/hpc/

[^3_17]: https://www.wildberries.ru/catalog/tags/zhestkii-disk-22tb

[^3_18]: https://www.vistlan.ru/catalog/serveryi_i_shd/komplektuyuschie_dlya_serverov/servernyie_nakopiteli/MTFDHAL3T8TDP_1AT1ZABYY/

[^3_19]: https://www.layta.ru/kommutatory/32/

[^3_20]: https://bs-opt.ru/gotovye-servery/sistemy-khraneniya-dannykh/shd-lenovo/sistema-khraneniya-dannykh-skhd-lenovo-dm-controller-dm3010h-2u12-lff/?popularAction=ADD2BASKET\&productId=

[^3_21]: http://arxiv.org/pdf/2207.11407.pdf

[^3_22]: https://v-color.net/collections/ddr5-reg-dimm

[^3_23]: https://russian.alibaba.com/product-detail/Hynix-64GB-DDR5-5600-ECC-REG-1601608400369.html

[^3_24]: https://v-color.net/collections/sever-memory-vcolor

[^3_25]: https://russian.alibaba.com/product-detail/Samsung-64GB-DDR5-5600-ECC-REG-1601608514045.html

[^3_26]: https://www.regard.ru/reciept/26892370/servernaia-operativnaia-pamiat-ddr5-dimm

[^3_27]: https://shop.nav-it.ru/catalogue/raid_kontrollery_karty_i_platy_upravleniya/mellanox_connectx_6_dx_en_adapter_card_25gbe_dual_port_sfp28_pcie_4_0_x8_no_crypto_tall_bracket_1_ye/

[^3_28]: https://wit.ru/parts/mcx623106ac-cdat-mellanox-connectx-6-dx-en-adapter-card-100gbe-dual-port-qsfp56-pcie-4.0-x16-crypto-and-secure-boot-tall-bracket-1112812

[^3_29]: https://serverflow.ru/config/servernaya-platforma-supermicro-superserver-6029u-e1cr4t-2u-12lff-4x-u-2-2x-750w-2x-lga3647/

[^3_30]: https://memory.net/memory-prices/

[^3_31]: https://market.yandex.ru/card/setevoy-adapter-mellanox-connectx-6-lx-en-adapter-card-25gbe-dual-port-sfp28-pcie-40-x8-no-crypto-tall-bracket-1-year/4300319168

[^3_32]: https://www.mayabilgisayar.com/ru/product-page/mellanox-connectx-6-mcx623106an-cdat

[^3_33]: https://serverflow.ru/catalog/servery/servernaya-platforma-supermicro-as-2024us-trt-2u-12lff-4x-u-2-2x-1600w-2x-sp3/

[^3_34]: https://www.newegg.com/p/pl?d=ddr5+ecc+64gb

[^3_35]: https://vps-v.ru/shop/setevaya-karta-mellanox-connectx-6-dx-en-adapter-card-25gbe-dual-port-sfp28-pcie-4-0-x8-no-crypto-tall-bracket-1-year-mcx621102an-adat/

[^3_36]: https://lenovopress.lenovo.com/lp1352-thinksystem-mellanox-connectx-6-dx-100gbe-qsfp56-ethernet-adapter

[^3_37]: https://www.kns.ru/catalog/servery/supermicro/

[^3_38]: https://www.tdsystem.ru/catalog/nlc-116518/?linerow=4

[^3_39]: https://russian.alibaba.com/product-detail/High-performance-Network-Card-Mellanox-ConnectX-1601151615984.html

[^3_40]: https://kvan.tech/catalog/komplektuyushchie/pci-moduli/setevye-adaptery/setevye-adaptery-mellanox/setevaya-karta-mellanox-ethernet-adapter-thinksystem-connectx-6-dx-100gbe-qsfp56-2-port-pcie-etherne/

[^3_41]: https://supermicro-russia.ru

[^3_42]: https://kvan.tech/catalog/komplektuyushchie/pci-moduli/setevye-adaptery/setevye-adaptery-mellanox/setevaya-karta-mellanox-connectx-6-dx-dual-port-100gbe-qsfp56-network-adapter-full-height/


---

# Добавь ссылки на конкретные позиции в магазинах по всем видам оборудования, чтобы я понимал, откуда ты брал цены.

Вот список конкретных компонентов с ссылками на российские магазины (актуальность на конец 2025 года).

> **Обратите внимание:** Цены на сложное оборудование (платформы, коммутаторы 100G) часто указаны «по запросу», так как зависят от текущего курса валют и статуса поставки (параллельный импорт или официальный канал). В таких случаях я привожу ссылки на карточки товаров, где можно запросить КП, или цены с маркетплейсов для ориентира.

### 1. Storage-узлы (MinIO)

Нам нужна платформа с большим количеством дисков (LFF) и сами диски.

* **Платформа (Chassis + MB + PSU):** Supermicro 2U 12LFF
    * *Пример:* Supermicro SuperServer 6029U-E1CR4T (2U, 12 дисков 3.5").
    * *Магазин:* ServerFlow  или Delivit.[^4_1][^4_2]
    * *Цена:* ~350 000 – 450 000 ₽ (зависит от комплектации БП и райзеров).
* **Диски (HDD) 22TB:**
    * *Модель:* WD Gold 22TB (WD221KRYZ) или Seagate Exos X22.
    * *Магазин:* Regard, Ozon, Wildberries.[^4_3][^4_4][^4_5]
    * *Цена:* ~50 000 – 65 000 ₽ за шт.
* **Диски под кэш (NVMe) 3.84TB:**
    * *Модель:* Micron 7450 PRO / Samsung PM9A3 U.2.
    * *Магазин:* Regard, Vistlan, Navigator.[^4_6][^4_7][^4_8]
    * *Цена:* ~55 000 – 70 000 ₽.
* **Сетевая карта 100GbE:**
    * *Модель:* Mellanox ConnectX-6 Dx Dual Port 100GbE.
    * *Магазин:* Wit.ru, Kvantech.[^4_9][^4_10]
    * *Цена:* ~90 000 – 120 000 ₽.


### 2. Compute-узлы (Spark)

Здесь основной бюджет — это оперативная память и CPU.

* **Процессор (CPU):**
    * *Модель:* Intel Xeon Gold 6430 (32 ядра).
    * *Магазин:* Regard, Price.ru (сводка), ServerFlow.[^4_11][^4_12][^4_13]
    * *Цена:* ~135 000 – 160 000 ₽ за шт.
* **Оперативная память (RAM) 64GB DDR5:**
    * *Модель:* Samsung 64GB DDR5 ECC REG 4800/5600MHz.
    * *Магазин:* ServerFlow, Regard, Avito (для проверки рынка).[^4_14][^4_15][^4_16]
    * *Цена:* ~25 000 – 35 000 ₽ за планку.
* **Платформа Compute (High Density):**
    * *Модель:* QCT QuantaGrid (альтернатива Supermicro, доступная в РФ) или Supermicro AS-2024US.
    * *Магазин:* Kvantech, ServerFlow, H200.[^4_17][^4_18][^4_19]
    * *Цена:* ~400 000 – 600 000 ₽ (за платформу без CPU/RAM).


### 3. Сетевое ядро (Network Backbone)

Самая дефицитная позиция, часто под заказ.

* **Коммутатор 100GbE (32 порта):**
    * *Модель:* Eltex MES5500-32 (Российский реестр, доступен официально).
    * *Магазин:* Born-Shop, Layta, Eltex-MSK.[^4_20][^4_21][^4_22]
    * *Цена:* ~3 500 000 – 4 700 000 ₽ (Цена сильно варьируется от проекта к проекту, "розничная" цена часто заградительная, в проекте будет дешевле).
    * *Альтернатива:* Б/у Mellanox SN2700 (на Avito/Nag.ru) будет стоить в районе 500 000 – 800 000 ₽, но без гарантии вендора.

**Совет:** Для таких закупок (общий бюджет >30 млн) не покупайте "в корзину". Используйте эти ссылки как референс цены, составьте спецификацию (BoM) и отправьте запрос в 3-4 системных интегратора (Крок, Softline, Jet, Servermall, It-Grad). Они дадут проектную скидку (обычно 10-20% от цен интернет-магазинов).
<span style="display:none">[^4_23][^4_24][^4_25][^4_26][^4_27][^4_28][^4_29][^4_30]</span>

<div align="center">⁂</div>

[^4_1]: https://serverflow.ru/config/servernaya-platforma-supermicro-superserver-6029u-e1cr4t-2u-12lff-4x-u-2-2x-750w-2x-lga3647/

[^4_2]: https://delivit.ru/catalog/servery/stoechnye/2-processornye/supermicro/servernaya-platforma-supermicro-2u-no-cpu-2-scalable-tdp-70-205w-no-dimm-12-sataraid-hdd-12-lff-2x10/

[^4_3]: https://www.regard.ru/reciept/30948123/servernye-zestkie-diski-hdd-22-tb

[^4_4]: https://www.ozon.ru/product/western-digital-22-tb-vnutrenniy-zhestkiy-disk-wd221kryz-924960530/

[^4_5]: https://www.wildberries.ru/catalog/tags/zhestkii-disk-22tb

[^4_6]: https://www.regard.ru/reciept/434196/servernye-ssd-nakopiteli-384-tb

[^4_7]: https://www.vistlan.ru/catalog/serveryi_i_shd/komplektuyuschie_dlya_serverov/servernyie_nakopiteli/MTFDHAL3T8TDP_1AT1ZABYY/

[^4_8]: https://shop.nav-it.ru/catalogue/servernye_zhestkie_diski_ssd/micron_7450_pro_3_84tb_nvme_u_3_15mm_ssd_enterprise_solid_state_drive_1_year_oem/

[^4_9]: https://wit.ru/parts/mcx623106ac-cdat-mellanox-connectx-6-dx-en-adapter-card-100gbe-dual-port-qsfp56-pcie-4.0-x16-crypto-and-secure-boot-tall-bracket-1112812

[^4_10]: https://kvan.tech/catalog/komplektuyushchie/pci-moduli/setevye-adaptery/setevye-adaptery-mellanox/setevaya-karta-mellanox-ethernet-adapter-thinksystem-connectx-6-dx-100gbe-qsfp56-2-port-pcie-etherne/

[^4_11]: https://price.ru/processory/intel-xeon-gold-6430/

[^4_12]: https://serverflow.ru/catalog/komplektuyushchie/protsessory/protsessor-intel-xeon-gold-6430-32c-64t-2ghz-3-6ghz-205w/

[^4_13]: https://www.regard.ru/product/425975/servernyi-processor-intel-xeon-gold-6430-oem

[^4_14]: https://www.regard.ru/product/741968/operativnaia-pamiat-64gb-ddr5-6400mhz-samsung-ecc-rdimm-m321r8ga0pb2-ccp-oem

[^4_15]: https://www.avito.ru/moskva/tovary_dlya_kompyutera/servernaya_pamyat_ddr5_ecc_samsung_64_gb_4800_7680188674

[^4_16]: https://serverflow.ru/catalog/komplektuyushchie/operativnaya-pamyat/operativnaya-pamyat-64gb-ddr5-ecc-reg-samsung-5600mhz-2rx4/

[^4_17]: https://serverflow.ru/catalog/servery/server-supermicro-as-2024us-trt-2u-12lf/

[^4_18]: https://kvan.tech/catalog/servery-i-vychislitelnye-sistemy/server-qct-quantagrid-d52bq-2u/

[^4_19]: https://h200.ru/katalog/item/qct_quantagrid_s44nl_1u/

[^4_20]: https://born-shop.ru/catalog/212970.html

[^4_21]: https://www.layta.ru/elteks-mes5500-32.html

[^4_22]: https://eltexsl.ru/product/mes5500-32/

[^4_23]: https://luis.ru/p/2897138

[^4_24]: https://www.elektro.ru/product/ethernet-kommutator_mes5500-32_2x10gbase-r_sfp_32_x_40gbase-r_qsfp_100gbase-r_qsfp28_l3_2_slota_dlya_moduley_pitaniya/

[^4_25]: https://server.tkasiatorg.ru/catalog/qct_servernoe_oborudovanie/server-quantagrid-d52bq-2u

[^4_26]: https://platb24.ru/product/0268214

[^4_27]: https://kvan.tech/catalog/servery-i-vychislitelnye-sistemy/server-qct-quantagrid-d74h-7u/

[^4_28]: https://www.nix.ru/autocatalog/networking_eltex/Kommutator-ELTEX-MES5500-32-1x10-100-1000BASE-T-OOB-2x10GBASE-R-SFP-plus-32x40GBASE-R-QSFP-plus-100GBASE-R-QSFP28_795191.html

[^4_29]: https://kvan.tech/catalog/servery-i-vychislitelnye-sistemy/server-qct-quantagrid-t43z-2u/

[^4_30]: https://www.open-vision.ru/catalog/network-equipment/commutatori/eltex-mes5500-32/


---

# Стоит ли мне включать minio в свой основонй kubernetes-кластер (в отдельном namespace) -- или лучше сделать его отдельным kubernetes-кластером?

Учитывая ваши масштабы (1 ПБ данных) и характер нагрузки (Spark, который генерирует тысячи подов), ответ однозначный: **Сделайте отдельный Kubernetes-кластер для MinIO** (или даже рассмотрите запуск вне K8s, на «голом железе»).

Смешивать Storage (MinIO) и Compute (Spark) в одном кластере на таких объемах — это **плохая идея**.

Вот 4 причины, почему вам нужна изоляция (Separate Cluster):

### 1. Проблема "Шумных соседей" и ETCD

Spark — это "убийца" Kubernetes API.

* Когда вы запускаете тяжелую задачу на PySpark, драйвер может запросить создание сотен и тысяч экзекьюторов (executor pods) одновременно.
* Это создает колоссальную нагрузку на `etcd` и Control Plane кластера.
* Если `etcd` начнет "захлебываться", у вас могут начаться таймауты в API. Если в этом же кластере живет MinIO, Kubernetes может посчитать, что ноды хранения "NotReady", и начать (безуспешно) перебалансировать стейтфул-нагрузку.
* **Итог:** Ваш Spark-джоб может случайно "положить" доступ к данным для всей компании.


### 2. Разный жизненный цикл (Lifecycle Management)

* **Compute-кластер** (Spark/Airflow/Apps) должен быть динамичным. Вы будете часто обновлять версию Kubernetes, обновлять драйверы, ставить эксперименты, возможно, даже пересоздавать кластер целиком (Blue/Green деплоймент кластеров).
* **Storage-кластер** (MinIO) должен быть скучным, стабильным и "вечным". Вы не хотите перегружать ноды с петабайтом данных только потому, что вам нужно обновить версию Docker или CNI-плагина для нового приложения.
* Разделение позволяет обновлять вычислительный контур хоть каждый день, не рискуя целостностью данных.


### 3. Сложность сетевой настройки (CNI)

Для MinIO на 100GbE сети критически важна производительность.

* В общем кластере вам придется использовать один CNI (например, Calico или Cilium) на всех.
* В выделенном кластере MinIO вы можете настроить сеть более агрессивно: использовать `HostNetwork` (чтобы избежать оверхеда NAT и инкапсуляции VXLAN) или специфические настройки Multus, не боясь сломать сетевую политику для обычных приложений.


### 4. Защита от человеческого фактора (Taints \& Tolerations)

Если вы держите всё в одном кластере, вам придется обвешать Storage-ноды жесткими `Taints`, а на поды MinIO повесить `Tolerations` и `NodeAffinity`.
Один раз кто-то ошибется в конфигурации YAML для Spark-джоба (забыв указать NodeSelector), и тяжелый Spark-экзекьютор прилетит на Storage-ноду, выжирая CPU и RAM, которые нужны MinIO для кэширования и Erasure Coding.
Физическое разделение кластеров делает такую ошибку невозможной.

### Рекомендация по архитектуре

**Вариант А (Dedicated K8s Cluster) — Рекомендуемый**
Разверните маленький, стабильный K8s-кластер исключительно для MinIO.

* Используйте **MinIO Operator**. Он великолепен, берет на себя управление дисками и сертификатами.
* В этот кластер заходят только админы хранения.

**Вариант Б (Bare Metal / Systemd) — Для параноиков производительности**
На объемах в 1 ПБ многие инженеры вообще отказываются от K8s для слоя хранения.

* Запустите MinIO как обычный сервис `systemd` на Linux.
* **Плюс:** Нет оверхеда K8s, нет слоев абстракции сети, прямой доступ к дискам. Максимальная производительность.
* **Минус:** Теряете удобство управления через YAML и Operator.

**Итог:**
Не делайте общий namespace. Делайте **отдельный кластер**. Ваши нервы при первом же крупном обновлении K8s скажут вам спасибо.

---

# А стоит ли мне размещать Spark-кластер в том же Kubernetes-кластере, что и все мои веб-сервисы, Kafka и вспомогательные БД? Или лучше вытащить Spark-кластер в отдельный Kubernetes-кластер?

В вашем масштабе (1 петабайт данных, сотни нод, тысячи подов) **крайне рекомендуется вынести Spark-кластер в отдельный Kubernetes-кластер**.

Попытка сэкономить на администрировании и смешать всё в одном (Shared Cluster) приведёт к тому, что Spark начнёт "убивать" ваши веб-сервисы и Kafka.

Вот 3 главные причины, почему разделение необходимо:

### 1. Проблема "DDoS-атаки" на Kubernetes Control Plane

Spark на K8s работает очень агрессивно по отношению к API-серверу и `etcd`.

* **Сценарий:** Вы запускаете тяжелый джоб (или 10 джобов одновременно). Spark-драйвер запрашивает создание 2000 подов-экзекьюторов.
* **Последствие:** `etcd` получает шквал запросов на запись. В общем кластере это приведет к резкому росту латентности API.[^6_1][^6_2]
* **Риск:** Контроллеры ваших веб-сервисов (Ingress, Deployments) и Kafka (если она в K8s) перестанут получать обновления статусов. `Liveness/Readiness` пробы могут начать падать по таймауту, и K8s начнёт перезагружать ваши стабильные веб-сервисы, считая их мертвыми.


### 2. "Шумные соседи" и борьба за сеть

Даже если вы идеально настроите лимиты CPU/RAM (ResourceQuotas), вы не сможете так же легко изолировать **сетевой ввод-вывод (Network I/O)** и **дисковый I/O** (для Shuffle).

* Spark во время фазы Shuffle забивает сетевой канал "восточно-западным" (east-west) трафиком между нодами.
* В общем кластере это приведет к тому, что условный Kafka-брукер или веб-сервис начнет получать ответы от базы данных с задержкой в сотни миллисекунд вместо единиц. Ваша Kafka начнет терять синхронизацию ISR (In-Sync Replicas).


### 3. Разные требования к обновлению и стабильности (Lifecycle)

* **Service Cluster (Web/Kafka):** Требует высокой доступности (HA), осторожных обновлений (Rolling Update по одному поду), стабильных версий K8s. Здесь аптайм — царь.
* **Compute Cluster (Spark):** Это "молотилка". Поды живут от минут до часов. Здесь можно и нужно использовать Spot-инстансы (прерываемые ВМ), агрессивный автомасштабинг (Cluster Autoscaler) с нуля до сотен нод и обратно.
* Смешивание этих двух миров усложняет эксплуатацию: вы будете бояться обновить K8s, чтобы не сломать Spark, или наоборот.


### Рекомендуемая архитектура

1. **Cluster A (Services):** Стабильный, "дорогой" кластер. Веб-сервисы, BI-инструменты (Superset/Tableau), Kafka, Metastore (Hive/Glue). Здесь живут долгоживущие поды.
2. **Cluster B (Spark Compute):** Эластичный, "дешевый" кластер.
    * Сюда ставится **Spark Operator**.
    * Здесь настроен агрессивный Cluster Autoscaler.
    * Ноды могут быть без Persistent Storage (кроме временного NVMe для shuffle).
    * Если этот кластер "умрет" или зависнет `etcd`, ваши бизнес-сервисы в Кластере А продолжат работать, просто аналитика встанет на паузу.

**Исключение:** Если у вас *маленький* Spark (десятки подов, терабайты данных) и редкие запуски (раз в ночь), можно жить в одном кластере с `ResourceQuota` и `NodePools` (изолированными группами нод). Но для петабайтного Data LakeHouse — только разделение.[^6_3]
<span style="display:none">[^6_10][^6_11][^6_12][^6_13][^6_14][^6_15][^6_16][^6_17][^6_18][^6_19][^6_20][^6_21][^6_22][^6_23][^6_24][^6_25][^6_26][^6_27][^6_28][^6_29][^6_30][^6_31][^6_32][^6_4][^6_5][^6_6][^6_7][^6_8][^6_9]</span>

<div align="center">⁂</div>

[^6_1]: https://github.com/etcd-io/etcd/issues/10711

[^6_2]: https://github.com/kubernetes/kubernetes/issues/93280

[^6_3]: https://blog.cellenza.com/en/data/using-spark-with-kubernetes-k8s/

[^6_4]: http://arxiv.org/pdf/1708.05746.pdf

[^6_5]: https://arxiv.org/pdf/2211.11487.pdf

[^6_6]: http://downloads.hindawi.com/journals/scn/2017/3910126.pdf

[^6_7]: http://arxiv.org/pdf/2306.03672.pdf

[^6_8]: https://arxiv.org/pdf/2309.00269.pdf

[^6_9]: https://arxiv.org/pdf/2411.11326.pdf

[^6_10]: http://arxiv.org/pdf/1704.06738.pdf

[^6_11]: https://arxiv.org/pdf/2409.16919.pdf

[^6_12]: https://spark.apache.org/docs/latest/running-on-kubernetes.html

[^6_13]: https://spark.apache.org/docs/3.5.2/running-on-kubernetes.html

[^6_14]: https://aws.amazon.com/blogs/containers/best-practices-for-running-spark-on-amazon-eks/

[^6_15]: https://www.chaosgenius.io/blog/spark-on-kubernetes/

[^6_16]: https://www.cloudbees.com/blog/spark-on-kubernetes-the-hows-and-the-whys

[^6_17]: https://stackoverflow.com/questions/48179637/is-it-possible-to-isolate-spark-cluster-nodes-for-each-individual-application

[^6_18]: https://github.com/kubernetes/kubernetes/issues/66896

[^6_19]: https://doc.dataiku.com/dss/latest/user-isolation/capabilities/kubernetes.html

[^6_20]: https://tresata.ai/spark-on-k8s/

[^6_21]: https://aws.amazon.com/blogs/containers/optimizing-spark-performance-on-kubernetes/

[^6_22]: https://www.reddit.com/r/kubernetes/comments/1824l6g/running_apache_spark_on_k8s/

[^6_23]: https://www.reddit.com/r/kubernetes/comments/jrimq9/why_is_etcd_writing_so_much_on_an_idle_cluster/

[^6_24]: https://stackoverflow.com/questions/61565751/why-am-i-not-able-to-run-sparkpi-example-on-a-kubernetes-k8s-cluster

[^6_25]: https://note.wcoder.com/BigData/files/running-apache-spark-on-kubernetes-best-practices-and-pitfalls-iteblog.com.pdf

[^6_26]: https://slickfinch.com/kubernetes-cluster-performance-tuning-etcd-speed/

[^6_27]: https://blog.duyet.net/2020/05/spark-on-k8s.html

[^6_28]: https://www.linkedin.com/pulse/spark-kubernetes-practitioners-guide-mich-talebzadeh-ph-d-

[^6_29]: https://github.com/etcd-io/etcd/issues/13648

[^6_30]: https://stackoverflow.com/questions/71894721/spark-on-kubernetes-how-to-improve-my-performance

[^6_31]: https://www.ksolves.com/blog/big-data/spark/managing-and-monitor-apache-spark-on-kubernetes

[^6_32]: https://github.com/etcd-io/etcd/discussions/18381


---

# Сравни стоимость кластера для хранения 1 Пб данных на Microsoft SQL Server и на S3 + Apache Iceberg + PySpark. Цены смотри для России. Коэффициент резервирования считаем 2 для обеих систем.

Ниже приведено прямое сравнение стоимости реализации хранилища на 1 ПБ полезных данных.

### Итоговая оценка (Capex)

* **Microsoft SQL Server DWH:** ~227 млн рублей.
* **Open Source Data Lakehouse:** ~32 млн рублей.
* **Разница:** **7.1 раза**.

![Сравнение стоимости владения (TCO) для 1 ПБ данных (Декабрь 2025)](https://ppl-ai-code-interpreter-files.s3.amazonaws.com/web/direct-files/66ec1103c7295c3145b5105c9d6e3c42/9541a0c4-54b5-45a9-b3b6-c32e43c36f10/270f7def.png)

Сравнение стоимости владения (TCO) для 1 ПБ данных (Декабрь 2025)

### Детальный разбор затрат

#### 1. Microsoft SQL Server Enterprise

Это решение — "золотая клетка". Главная статья расходов здесь — не диски, а **лицензирование ядер процессора**.

* **Оборудование (~48 млн ₽):**
    * Для SQL Server нельзя использовать "медленное" железо, иначе база встанет колом. Вам потребуются Enterprise Flash массивы (или All-Flash) для логов транзакций и TempDB, а также мощные процессоры с высокой частотой.
    * *Оценка:* Взята стоимость оборудования для Data Lakehouse + 50% наценки за требования к Enterprise-классу (RAID-контроллеры, SAN-фабрика).
* **Лицензии (~179 млн ₽):**
    * SQL Server Enterprise лицензируется **по ядрам**.
    * Для обработки 1 ПБ данных в реляционной СУБД вам понадобится кластер минимум из 16 мощных серверов (по 32 ядра каждый), итого **512 ядер**. Это даже мало для такой нагрузки.
    * Стоимость лицензии (Pack of 2 Cores) ~ \$7,000 (по параллельному импорту или через партнеров в СНГ цены могут быть еще выше).
    * *Расчет:* `(512 ядер / 2) * $7,000 * 100₽/$ = 179 200 000 ₽`.
    * *Примечание:* И это без учета Software Assurance (подписки на обновления), которая добавит еще 25% в год.


#### 2. Open Source Data Lakehouse (S3 + Iceberg)

Это решение — "инженерный конструктор". Вы платите только за железо.

* **Оборудование (~32 млн ₽):**
    * Как мы рассчитывали ранее: 8 Storage-нод с дешевыми HDD (MinIO) + 10 Compute-нод (Spark) + 100GbE сеть.
    * MinIO обеспечивает отказоустойчивость программно (Erasure Coding), что позволяет использовать обычные серверы без дорогих RAID-контроллеров.
* **Лицензии (0 ₽):**
    * **MinIO:** Используем версию под лицензией GNU AGPL v3 (бесплатно).
    * **Apache Iceberg:** Open Source (Apache 2.0).
    * **Apache Spark:** Open Source (Apache 2.0).
    * *Риск:* Вы не платите за лицензии, но платите зарплату инженерам, которые умеют это настраивать. Однако, зарплата команды за год (даже 20-30 млн ₽) всё равно меньше стоимости **одной** закупки лицензий Microsoft.


### Вывод

Пытаться построить хранилище на 1 ПБ на проприетарной RDBMS (SQL Server / Oracle) в 2025 году в России — это экономическое самоубийство.

* **SQL Server** имеет смысл только для витрин данных (Data Marts) размером до 5-10 ТБ, где нужна сверхбыстрая транзакционная логика и сложный SQL.
* **Data Lakehouse** — безальтернативный вариант для основного "холодного" и "теплого" слоя хранения.
<span style="display:none">[^7_1][^7_10][^7_11][^7_12][^7_13][^7_14][^7_15][^7_16][^7_17][^7_18][^7_19][^7_2][^7_20][^7_21][^7_22][^7_23][^7_24][^7_25][^7_26][^7_27][^7_28][^7_29][^7_3][^7_30][^7_31][^7_32][^7_33][^7_34][^7_4][^7_5][^7_6][^7_7][^7_8][^7_9]</span>

<div align="center">⁂</div>

[^7_1]: https://www.semanticscholar.org/paper/ba555d53fc07bb1d9c62230a51f5542350b854f0

[^7_2]: https://www.semanticscholar.org/paper/4843f975e53b00f2a7d15c2c76e6392910f13040

[^7_3]: https://www.semanticscholar.org/paper/bdb927de518c267dfc09e3c1b1b17ad4cd23e458

[^7_4]: http://link.springer.com/10.1007/978-1-4302-4771-5_15

[^7_5]: http://www.atlantis-press.com/php/paper-details.php?id=25843744

[^7_6]: https://www.semanticscholar.org/paper/1ed64261f1b8476f635c7b7f909b240ce73ad016

[^7_7]: https://www.semanticscholar.org/paper/c3639d9a1697ade1a0c769b5f44edd28443f3885

[^7_8]: https://www.taylorfrancis.com/books/9781482219234

[^7_9]: https://www.semanticscholar.org/paper/891aca1bc3edcfba471e1d86988649a0b7ef54cb

[^7_10]: https://www.taylorfrancis.com/books/9780203498743

[^7_11]: https://www.tandfonline.com/doi/pdf/10.1080/09540091.2024.2323059?needAccess=true

[^7_12]: http://arxiv.org/pdf/2404.00311.pdf

[^7_13]: http://thesai.org/Downloads/Volume7No2/Paper_11-Pricing_Schemes_in_Cloud_Computing_An_Overview.pdf

[^7_14]: https://www.microsoft.com/en-us/sql-server/sql-server-2022-pricing

[^7_15]: https://www.microsoft.com/tr-tr/sql-server/sql-server-2022-pricing

[^7_16]: https://www.cdw.com/product/microsoft-sql-server-2022-enterprise-license-2-cores/7299197

[^7_17]: https://www.reddit.com/r/SQLServer/comments/10a87pn/does_anyone_know_approx_price_of_sql_server/

[^7_18]: https://airbyte.com/data-engineering-resources/sql-server-pricing

[^7_19]: https://www.microsoft.com/en-us/sql-server/sql-server-2019-pricing

[^7_20]: https://www.elite.com.eg/product-page/dell-powerstore-500t-storage/

[^7_21]: https://www.reddit.com/r/storage/comments/vdr6ql/pricing_examples_for_1pb_cheap_enterprise_storage/

[^7_22]: https://365cloudstore.com/product/sql-server-2022-enterprise/

[^7_23]: https://royaldiscount.com/shop/sql-server-enterprise-2-core-license-sa-open-business/

[^7_24]: https://www.reddit.com/r/storage/comments/1ic2u30/alletrapurepowerstore_pricing_help/

[^7_25]: https://www.ibm.com/flashsystem/pricing

[^7_26]: https://www.trustedtechteam.com/products/microsoft-sql-server-2022-enterprise-2-core-license-w-software-assurance

[^7_27]: https://o365hq.com/license/CSP-DG7GMGF0FKZV-0004

[^7_28]: https://icgintl.com/dell-emc-powerstore-price-calculator

[^7_29]: https://wasabi.com/blog/data-management/on-premises-vs-cloud-storage

[^7_30]: https://www.connection.com/product/microsoft-corp.-csp-sql-server-2022-enterprise-2-core-license-pack-1-year-term-paid-monthly/dg7gmgf0m7xv-0002/41629334

[^7_31]: https://www.hakunamatatatech.com/our-resources/blog/sql-server-enterprise

[^7_32]: https://www.dell.com/en-us/shop/ipovw/powerstore-t-series

[^7_33]: https://www.45drives.com/blog/cloud-storage/total-cost-of-ownership-cloud-vs-on-premise-storage/

[^7_34]: https://www.gotomojo.com/storage/dell-emc/powerstore/


---

### 1. Можно ли купить SQL Server в России в 2025 году?

**Да, можно, но с нюансами.**

Официально Microsoft приостановила продажи в РФ, но рынок адаптировался:

1. **Параллельный импорт:** Крупные интеграторы и магазины ПО (например, Softline, Syssoft, Allsoft) продают бессрочные лицензии (Perpetual), ввезенные через третьи страны. Это полностью легально с точки зрения текущего законодательства РФ.
2. **SPLA (Аренда):** Многие российские облачные провайдеры и хостеры (Mnogobyte, Unihost ) продолжают предоставлять лицензии в аренду по модели SPLA (Services Provider License Agreement). Вы платите ежемесячно за используемые ядра. Это часто проще, чем покупать "коробку" за десятки миллионов сразу.[^8_1][^8_2]
3. **ОЕМ-лицензии:** Поставляются в комплекте с серверами, ввезенными по параллельному импорту.

**Риски:** Главный риск — отсутствие официальной технической поддержки вендора (Microsoft Support). Если вы словите баг в ядре SQL Server на 1 ПБ данных, вам придется надеяться только на российских консультантов или патчить своими силами (что невозможно для закрытого кода).

***

### 2. Нужен ли Enterprise Edition для 1 ПБ данных?

Если вы решите остаться на SQL Server, то ответ категоричный: **ДА, вам нужен Enterprise.** Standard Edition физически не потянет ваши требования.

Вот почему **SQL Server Standard** умрет на ваших объемах:

#### А. Лимит оперативной памяти (Buffer Pool)

* **Standard:** Максимум **128 ГБ** RAM на инстанс.[^8_3][^8_4]
* **Проблема:** Для базы в 1 ПБ (1 000 000 ГБ) кэш в 128 ГБ — это капля в море (0.01%). Любой запрос будет поднимать данные с диска, убивая производительность I/O.
* **Enterprise:** Лимит — максимум ОС (десятки терабайт). Вам нужно минимум 2-4 ТБ RAM для комфортной работы с горячими данными, и Standard вам этого не даст.


#### Б. Секционирование (Partitioning) и Columnstore

* **Хорошая новость:** Начиная с версии 2016 SP1, *Table Partitioning* и *Columnstore Indexes* доступны и в Standard Edition.[^8_3]
* **Плохая новость:** В Standard отсутствуют технологии параллелизма для секционированных таблиц (*Partition Table Parallelism*). Это значит, что сканирование вашей гигантской таблицы будет идти медленнее, не задействуя все ядра эффективно.


#### В. Лимит вычислительной мощности

* **Standard:** Ограничен **24 ядрами** (или 4 сокетами).[^8_5][^8_3]
* **Проблема:** Обработать петабайт данных на 24 ядрах — это задача на недели для одного отчета. Вам нужны сотни ядер, что доступно только в Enterprise (лимит — максимум ОС).


#### Г. Online Index Rebuild

* **Standard:** Перестроение индексов блокирует таблицу.
* **Проблема:** На таблице размером в 100 ТБ перестроение индекса может занять сутки. В Standard Edition таблица будет недоступна для пользователей всё это время. В Enterprise это делается онлайн.


### Резюме

Покупка SQL Server Standard для 1 ПБ — это деньги на ветер. Он просто не сможет "прожевать" такой объем из-за лимита в 128 ГБ RAM и 24 ядра.

**Ваш выбор:**

1. Либо **SQL Server Enterprise** (очень дорого, доступно через параллельный импорт/SPLA).
2. Либо (рекомендуемо) **миграция на Open Source стек** (Data Lakehouse), где нет искусственных ограничений на железо.
<span style="display:none">[^8_10][^8_11][^8_12][^8_13][^8_14][^8_15][^8_16][^8_17][^8_18][^8_19][^8_20][^8_21][^8_22][^8_23][^8_24][^8_25][^8_26][^8_27][^8_28][^8_29][^8_6][^8_7][^8_8][^8_9]</span>

<div align="center">⁂</div>

[^8_1]: https://unihost.com/microsoft-spla/?lang=ru

[^8_2]: https://mnogobyte.ru/spla_arenda.html

[^8_3]: https://docs.aws.amazon.com/prescriptive-guidance/latest/evaluate-downgrading-sql-server-edition/compare.html

[^8_4]: https://www.brentozar.com/archive/2014/12/sql-server-2012-standard-edition-max-server-memory-mb/

[^8_5]: https://softtrader.eu/microsoft-sql-server-standard-vs-enterprise-main-differences/

[^8_6]: https://www.semanticscholar.org/paper/c4cd1054b59f3c57777fabfa3edf9e65f8a10dea

[^8_7]: https://arxiv.org/pdf/1710.08023.pdf

[^8_8]: https://arxiv.org/pdf/2305.14818.pdf

[^8_9]: https://arxiv.org/pdf/2405.02506.pdf

[^8_10]: https://arxiv.org/pdf/1205.2889.pdf

[^8_11]: https://arxiv.org/pdf/2301.01095.pdf

[^8_12]: http://arxiv.org/pdf/1208.4166.pdf

[^8_13]: https://arxiv.org/pdf/2209.06977.pdf

[^8_14]: https://arxiv.org/pdf/2401.11162.pdf

[^8_15]: https://five.co/blog/sql-server-standard-vs-enterprise/

[^8_16]: https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2019?view=sql-server-ver17

[^8_17]: https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022?view=sql-server-ver17

[^8_18]: https://blog.servermania.com/sql-server-comparison

[^8_19]: https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?view=sql-server-ver17

[^8_20]: https://learn.microsoft.com/en-us/sql/relational-databases/partitions/partitioned-tables-and-indexes?view=sql-server-ver17

[^8_21]: https://one-soft.ru/microsoft-sql-server-2025-enterprise

[^8_22]: https://www.microsoft.com/ru-ru/licensing/licensing-programs/spla-program

[^8_23]: https://stackoverflow.com/questions/46276508/does-ms-sql-server-support-table-partitioning-by-list

[^8_24]: https://softcomputers.org/sql-server/microsoft-sql-server-2025/microsoft-sql-server-2025-enterprise/

[^8_25]: https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/sql-server-editions.html

[^8_26]: https://www.reddit.com/r/sysadmin/comments/1ekysej/sql_2022_standard_ram_limits/

[^8_27]: https://www.sqlshack.com/database-table-partitioning-sql-server/

[^8_28]: https://www.microsoft.com/ru-ru/licensing/product-licensing/sql-server

[^8_29]: https://straightpathsql.com/archives/2020/12/sql-server-should-i-move-from-enterprise-to-standard/


---

# А что имеется в виду под "приводит к большому количеству трансформаций" в задании?

Фраза *"приводит к большому количеству трансформаций"* в контексте вашего задания — это классический признак **плохой модели данных** и архитектурной проблемы, которую часто называют "Data Swamp" (Болото Данных) или "Спагетти-архитектура".

Вот что конкретно это означает для аналитика и инженера данных:

### 1. Данные не готовы к аналитике "из коробки"

В исходной системе данные лежат в формате, удобном для *приложений* (OLTP), а не для *отчетов* (OLAP).

* **Пример:** Чтобы посчитать простой отчет "Сколько денег принесли пациенты с диагнозом X за месяц", вам нужно:

1. Взять таблицу `Patients`.
2. Сджойнить с `MedicalRecords` (чтобы найти диагноз).
3. Сджойнить с `Invoices` (чтобы найти счета).
4. Сджойнить с `Payments` (чтобы понять, оплачен ли счет).
5. Распарсить JSON/XML поле внутри `MedicalRecords`, где врач в свободной форме написал диагноз.
6. Сконвертировать валюты, если банк добавил мультивалютность.

Каждое такое действие — это **трансформация**. Когда сценариев использования "невероятное множество", аналитикам приходится писать эти трансформации *каждый раз заново* или создавать сотни промежуточных таблиц (views), которые зависят друг от друга.

### 2. Проблема "Schema-on-Read" vs "Schema-on-Write"

В задании сказано, что объем данных — сотни терабайт. Скорее всего, это смесь структурированных таблиц и полуструктурированных данных (JSON, XML, логи, тексты врачей).

* **Трансформация:** Чтобы SQL Server мог работать с этим эффективно, сырые данные нужно каждый раз парсить, чистить, типизировать и перекладывать в нормализованные таблицы.
* Это "съедает" ресурсы процессора и время. Если данные лежат "как попало", то для каждого нового отчета нужно писать новый сложный ETL-процесс.


### 3. Дублирование логики (Reinventing the Wheel)

"Большое количество трансформаций" часто означает, что одну и ту же метрику (например, "Чистая Прибыль") разные отделы считают по-разному, трансформируя сырые данные своими уникальными скриптами.

* Отдел финансов: `Прибыль = (Сумма счетов - Расходы)`.
* Отдел медицины: `Прибыль = (Сумма *оплаченных* счетов - Зарплата врачей)`.
* В итоге система перегружена тысячами похожих, но не идентичных запросов, которые "молотят" одни и те же терабайты данных.


### Как это связано с вашей задачей?

Это подсказка, что вам нужно внедрить слой **Data Modeling** (например, медальонную архитектуру: Bronze -> Silver -> Gold).

* Вместо того чтобы делать трансформации "на лету" при каждом запросе (что долго и дорого), вы должны один раз трансформировать сырые данные в "Золотой" слой (витрины данных), где всё уже очищено, посчитано и готово к быстрому потреблению.

В текущей системе (SQL Server DWH) эти трансформации, видимо, выполняются либо в тяжелых View, либо в хранимых процедурах, которые выполняются *часами*, блокируя базу.

---

# Обнови таблцу с расчётами цен для on-premise с учётом тех конкретных цен на комплектуху, которую ты нашёл в магазинах.

Вот обновленная таблица с конкретными ценами из российских магазинов (актуально на декабрь 2025):

## Сводная стоимость Data Lakehouse (1 ПБ)

| Кластер | Стоимость (₽) |
| :-- | --: |
| **Storage (MinIO, 8 нод)** | 10 672 000 |
| **Compute (Spark, 10 нод)** | 21 740 000 |
| **Сетевая инфраструктура** | 8 500 000 |
| **Инфраструктура (стойка/ИБП)** | 1 500 000 |
| **ИТОГО** | **42 412 000** |

## Детальная комплектация

| Компонент | Цена за ед. (₽) | Кол-во | Источник | Ссылка |
| :-- | --: | --: | :-- | :-- |
| **HDD 22TB SATA** (Seagate Exos/WD Ultrastar) | 47 000 | 96 | Regard | [^10_1] |
| **NVMe 3.84TB U.2** (Cache/Shuffle) | 42 000 | 36 | Regard | [^10_2] |
| **RAM 64GB DDR5 ECC 6400** Samsung | 65 000 | 176 | srv-trade.ru | [^10_3] |
| **Intel Xeon Gold 6430** (32 cores) | 205 000 | 20 | shop.nav-it.ru | [^10_4] |
| **Mellanox CX-6 Dx 100GbE** (Dual) | 106 000 | 8 | 3logic.ru | [^10_5] |
| **Mellanox CX-6 Lx 25GbE** (Dual) | 40 000 | 10 | Оценка | - |
| **Платформа Storage** 2U 12LFF | 450 000 | 8 | ServerFlow | [^10_6] |
| **Платформа Compute** 2U Dual Socket | 600 000 | 10 | Оценка | - |
| **Коммутатор Eltex MES5500-32** | 4 000 000 | 2 | Born-Shop | [^10_7] |

### Стоимость одного узла

**Storage-узел (1 шт): 1 334 000 ₽**

- Платформа Supermicro 2U 12LFF: 450 000 ₽
- 12× HDD 22TB: 564 000 ₽
- 2× NVMe 3.84TB (кэш): 84 000 ₽
- 2× RAM 64GB (128GB): 130 000 ₽
- 1× NIC 100GbE: 106 000 ₽

**Compute-узел (1 шт): 2 174 000 ₽**

- Платформа 2U Dual Socket: 600 000 ₽
- 2× CPU Xeon Gold 6430: 410 000 ₽
- 16× RAM 64GB (1TB): 1 040 000 ₽
- 2× NVMe 3.84TB (shuffle): 84 000 ₽
- 1× NIC 25GbE: 40 000 ₽


### Ключевые выводы

1. **Основная статья расходов** — оперативная память (176 планок × 65 000 ₽ = 11.4 млн ₽, это 27% бюджета).
2. **Сетевая инфраструктура** обошлась в 8.5 млн ₽ из-за дорогих 100GbE коммутаторов Eltex (российский реестр, официальная поставка).
3. **Финальная стоимость ~42.4 млн ₽** — это почти на 30% выше первоначальной оценки, что типично для проектов, когда переходишь от "оценок" к реальным ценам поставщиков.[^10_3][^10_5][^10_1]
<span style="display:none">[^10_10][^10_11][^10_12][^10_13][^10_14][^10_15][^10_16][^10_17][^10_18][^10_19][^10_8][^10_9]</span>

<div align="center">⁂</div>

[^10_1]: https://www.regard.ru/reciept/30948123/servernye-zestkie-diski-hdd-22-tb

[^10_2]: https://www.regard.ru/reciept/434196/servernye-ssd-nakopiteli-384-tb

[^10_3]: https://srv-trade.ru/catalog/pamyat/drr5_pc51200_6400mhz_reg_ecc/modul_pamyati_samsung_m321r8ga0pb2_ccp_ddr5_6400_64gb_ecc_reg.html

[^10_4]: https://shop.nav-it.ru/catalogue/protsessory_2/tsentralnyy_protsessor_intel_xeon_gold_6430_32_cores_64_threads_2_1_3_4ghz_60m_ddr5_4400_2s_270w_oem/

[^10_5]: https://3logic.ru/products/mcx623106ac-cdat-connectx-6-dx-en-adapter-card-100gbe-dual-port-qsfp56-pcie-4-0-x16-crypto-and--90098/

[^10_6]: https://serverflow.ru/config/servernaya-platforma-supermicro-superserver-6029u-e1cr4t-2u-12lff-4x-u-2-2x-750w-2x-lga3647/

[^10_7]: https://born-shop.ru/catalog/212970.html

[^10_8]: https://arxiv.org/html/2501.10682v1

[^10_9]: http://arxiv.org/pdf/2406.02039.pdf

[^10_10]: http://arxiv.org/pdf/2503.22017.pdf

[^10_11]: http://arxiv.org/pdf/2411.03174.pdf

[^10_12]: https://serverflow.ru/catalog/komplektuyushchie/operativnaya-pamyat/operativnaya-pamyat-64gb-ddr5-ecc-reg-samsung-6400mhz-2rx4/

[^10_13]: https://www.regard.ru/product/741968/operativnaia-pamiat-64gb-ddr5-6400mhz-samsung-ecc-rdimm-m321r8ga0pb2-ccp-oem

[^10_14]: https://www.regard.ru/product/741968/operativnaia-pamiat-64gb-ddr5-6400mhz-samsung-ecc-reg

[^10_15]: https://mitcor.ru/servery-i-seti/servery/komplektuusie-k-serveram/servernaa-operativnaa-pamat/samsung/18914900/

[^10_16]: https://www.regard.ru/product/425975/servernyi-processor-intel-xeon-gold-6430-oem

[^10_17]: https://e2e4online.ru/catalog/item/pamyat-ddr5-rdimm-64gb-samsung-m321r8ga0pb2-ccp-1370316/

[^10_18]: https://serverorbit.com/mellanox-mcx623106an-cdat-connectx-6-dx-en-100gbe-qsfp-56-dual-optical-ports/

[^10_19]: https://shop.nag.ru/catalog/31464.komplektuyuschie-dlya-serverov-i-shd/02271.servernaya-operativnaya-pamyat/100379.m321r8ga0pb2-ccp


---

# Пересчитай и стоимость On-Premise DWH на MS SQL с учётом реальных цен на железо в российских магазинах. Добавь в таблицу ссылки на конкретные позиции, вставь именно эти цены, используй их при финальном расчёте.

Вот обновленная таблица для **Microsoft SQL Server DWH** с реальными ценами из российских магазинов:

## Сводная стоимость SQL Server DWH (1 ПБ)

| Статья | Стоимость (₽) |
| :-- | --: |
| **Оборудование (16 серверов)** | 72 019 776 |
| **Лицензии SQL Server Enterprise** | 1 952 276 480 |
| **Сетевая инфраструктура** | 8 500 000 |
| **Инфраструктура (стойка/ИБП)** | 1 500 000 |
| **ИТОГО** | **2 034 296 256** |

## Детальная комплектация с ценами

| Компонент | Цена за ед. (₽) | Кол-во | Источник | Ссылка |
| :-- | --: | --: | :-- | :-- |
| **Intel Xeon Platinum 8480+** (56 cores) | 898 098 | 32 | digital-tex.ru | [^11_1] |
| **RAM 128GB DDR5 5600** Samsung ECC | 115 000 | 128 | Оценка* | [^11_2] |
| **Samsung PM9A3 7.68TB** NVMe U.2 | 134 880 | 128 | Secumarket | [^11_3] |
| **Mellanox CX-6 Dx 100GbE** | 106 000 | 16 | 3logic.ru | [^11_4] |
| **Платформа 2U Dual Socket** | 600 000 | 16 | Оценка | - |
| **Коммутатор Eltex MES5500-32** | 4 000 000 | 2 | Born-Shop | [^11_5] |
| **Кабели и оптика** | 500 000 | 1 | - | - |
| **SQL Server 2022 Enterprise** (2-core pack) | 2 178 880 | 896 | Softmagazin.ru | [^11_6] |
| **Стойка, ИБП, PDU** | 1 500 000 | 1 | - | - |

*\*Цена на RAM 128GB рассчитана пропорционально цене 64GB (65 000 ₽) с учетом премии за больший объем.*

## Конфигурация одного сервера

**Стоимость: 4 501 236 ₽**

- **CPU:** 2× Intel Xeon Platinum 8480+ (56 cores) = 1 796 196 ₽
- **RAM:** 8× 128GB DDR5 (1 TB total) = 920 000 ₽
- **Storage:** 8× Samsung PM9A3 7.68TB (61.4 TB total) = 1 079 040 ₽
- **Network:** 1× Mellanox CX-6 Dx 100GbE = 106 000 ₽
- **Платформа:** 2U Dual Socket = 600 000 ₽


## Расчет лицензий

- **Общее количество ядер CPU:** 16 серверов × 2 CPU × 56 cores = **1792 ядра**
- **Необходимо 2-core packs:** 1792 ÷ 2 = **896 пакетов**
- **Стоимость лицензий:** 896 × 2 178 880 ₽ = **1 952 276 480 ₽**


## Сравнение решений

| Архитектура | Общая стоимость (₽) | Доля лицензий | Доля железа |
| :-- | --: | --: | --: |
| **Data Lakehouse** (Open Source) | 42 412 000 | 0% | 100% |
| **SQL Server DWH** | 2 034 296 256 | 96% | 4% |
| **Разница** | +1 991 884 256 | - | - |

### Ключевые выводы

1. **SQL Server DWH в 48 раз дороже** Data Lakehouse при тех же объемах данных.[^11_6][^11_3][^11_1]
2. **96% бюджета** уходит на лицензии SQL Server Enterprise, и только 4% — на реальное оборудование.
3. **Стоимость лицензий (почти 2 млрд ₽)** превышает стоимость всего Data Lakehouse почти в 46 раз.
4. Для SQL Server пришлось использовать **дорогие NVMe** вместо дешевых HDD (для MinIO), так как SQL Server крайне требователен к IOPS.
5. При таких объемах данных строить DWH на проприетарной СУБД в России экономически нецелесообразно.
<span style="display:none">[^11_10][^11_11][^11_12][^11_13][^11_14][^11_15][^11_16][^11_17][^11_18][^11_19][^11_20][^11_21][^11_22][^11_23][^11_24][^11_25][^11_26][^11_27][^11_28][^11_29][^11_30][^11_31][^11_32][^11_33][^11_34][^11_35][^11_36][^11_37][^11_38][^11_7][^11_8][^11_9]</span>

<div align="center">⁂</div>

[^11_1]: https://digital-tex.ru/catalog/komplektuyushchie/komplektuyushchie_dlya_serverov/protsessory/protsessor_intel_xeon_platinum_8480_pk8071305074801srm7h/

[^11_2]: https://www.regard.ru/product/707832/operativnaia-pamiat-128gb-ddr5-5600mhz-samsung-ecc-reg

[^11_3]: https://secumarket.ru/product/pm9a3-7-68tb-mzql27t6hbla-00a07-122584

[^11_4]: https://3logic.ru/products/mcx623106ac-cdat-connectx-6-dx-en-adapter-card-100gbe-dual-port-qsfp56-pcie-4-0-x16-crypto-and--90098/

[^11_5]: https://born-shop.ru/catalog/212970.html

[^11_6]: https://www.softmagazin.ru/microsoft/dg7gmgf0m7xv-0003/

[^11_7]: https://www.tandfonline.com/doi/pdf/10.1080/09540091.2024.2323059?needAccess=true

[^11_8]: http://arxiv.org/pdf/2404.00311.pdf

[^11_9]: http://thesai.org/Downloads/Volume7No2/Paper_11-Pricing_Schemes_in_Cloud_Computing_An_Overview.pdf

[^11_10]: https://www.microsoft.com/en-us/sql-server/sql-server-2022-pricing

[^11_11]: https://www.microsoft.com/ru-ru/sql-server/sql-server-2022-pricing

[^11_12]: https://www.bbrc.ru/catalog/item/sql_server_2022_enterprise_core_2_core_license_pack/

[^11_13]: https://airbyte.com/data-engineering-resources/sql-server-pricing

[^11_14]: https://www.hakunamatatatech.com/our-resources/blog/sql-server-enterprise

[^11_15]: https://russian.alibaba.com/g/dell-unity-xt-380-price.html

[^11_16]: https://www.router-switch.com/hpe-msa-storages-price.html

[^11_17]: https://o365hq.com/license/CSP-DG7GMGF0M7XV-0004

[^11_18]: https://www.karma-group.ru/catalog/dell-emc-unity/dell-unity-xt/unity-xt-480/

[^11_19]: https://hpe.metroconnect.co.th/wp-content/uploads/2023/10/HPE-MSA-2062-Storage-Array-a00094630enw.pdf

[^11_20]: https://www.dsaict.eu/shop/microsoft-sql-server-2022-enterprise-core-2-core-licenses-2137

[^11_21]: https://www.dell.com/en-uk/dt/solutions/oracle/storage-for-oracle.htm

[^11_22]: https://buy.hpe.com/tr/en/storage/disk-storage-systems/msa-storage/hpe-msa-2060-storage/p/1012748869

[^11_23]: https://journals.vsu.ru/sait/article/download/1293/1355

[^11_24]: https://arxiv.org/abs/2503.02240

[^11_25]: https://arxiv.org/pdf/2308.11258.pdf

[^11_26]: https://www.softmagazin.ru/soft/servernoe-po/sistemy-upravleniya-bazami-dannykh/tag-sql-server/

[^11_27]: https://spb.otc.ru/product/1240218-po-po-podpiske-elektronno-microsoft-sql-server-enterprise-2-core-license-pack-1-year/

[^11_28]: https://store.softline.ru/microsoft/7jq-00087-245436/

[^11_29]: https://www.ti-store.ru/ssd/samsung/mzql27t6hbla00a0

[^11_30]: https://3logic.ru/products/tsentralnyy-protsessor-intel-xeon-platinum-8480-56-cores-112-threads-2-0-3-8ghz-105m-ddr5-4800-175671/

[^11_31]: https://spb.otc.ru/product/1224935-po-po-podpiske-elektronno-microsoft-sql-server-enterprise-2-core-license-pack-3-year/

[^11_32]: https://www.regard.ru/product/400766/nakopitel-ssd-768tb-samsung-pm9a3-mzql27t6hbla-00a07-oem

[^11_33]: https://www.intel.com/content/www/us/en/products/sku/231746/intel-xeon-platinum-8480-processor-105m-cache-2-00-ghz/specifications.html

[^11_34]: https://serverflow.ru/catalog/komplektuyushchie/ssd-nakopiteli/samsung-pm9a3-7-68tb/

[^11_35]: https://www.nix.ru/autocatalog/ssd_samsung/SSD-768-Tb-U2-Samsung-PM9A3-MZQL27T6HBLA-00A07-OEM-25_587660.html

[^11_36]: https://serverflow.ru/catalog/komplektuyushchie/ssd-nakopiteli/ssd-nakopitel-samsung-pm9a3-7-6tb/

[^11_37]: https://flashcom.ru/market/server_operativ/404021-Modul_pamyati_Samsung_DDR5_128GB_5600MHz_RDIMM

[^11_38]: https://www.kns.ru/product/ssd-disk-samsung-pm9a3-7-68tb-mzql27t6hbla-00a07/


---

# А мне точно нужно именно 16 серверов для MS SQL? Может, хватит и меньшего? 4, 6 или 8 серверов?

Отличный вопрос! Вы правы, что надо пересмотреть архитектуру. Давайте разберемся, сколько серверов **реально** нужно для SQL Server на 1 ПБ данных.

## Проблема с моим первоначальным расчетом

Я неправильно спроектировал архитектуру. SQL Server — это **не распределенная система** (как Spark), и просто добавлять серверы для масштабирования хранения нельзя. Есть несколько реалистичных вариантов:

### Вариант 1: Монолит + внешнее хранилище (SAN/NAS)

**Самый типичный для Enterprise:**

- **2-4 сервера SQL** (AlwaysOn Always-On Availability Group для отказоустойчивости)
- Все вычисления и запросы идут на этих серверах
- **Данные хранятся на выделенном массиве хранения (СХД/SAN)**

Это решает проблему: вам не нужно 16 серверов, нужно всего **2-4 compute-сервера** и **отдельная система хранения данных (Storage Array)**.

### Вариант 2: Шардинг (вручную)

Разделить данные на 4-8 независимых баз данных по бизнес-логике (например, по регионам или годам). Но это требует изменения архитектуры приложения и не дает единого представления данных.

***

Давайте пересчитаю для **Варианта 1** (реалистичного):

---

# Да, пересчитай для варианта 1

Отлично! Вот пересчет для **реалистичного Варианта 1** (Compute + SAN):

## SQL Server DWH с внешним хранилищем

### Архитектура

- **4 мощных compute-сервера** (SQL Server с AlwaysOn AG)
- **10 storage-серверов** (SAN на базе дисковых полок, 2.6 ПБ сырой емкости)
- Данные хранятся на SAN, compute-серверы подключаются по 100GbE


### Общая стоимость: **527 115 984 ₽**

| Статья | Стоимость (₽) | Доля |
| :-- | --: | --: |
| **Compute-серверы** (SQL Server, 4 шт) | 15 846 864 | 3.0% |
| **Storage-серверы** (SAN, 10 шт) | 13 200 000 | 2.5% |
| **Лицензии SQL Server Enterprise** | 488 069 120 | **92.6%** |
| **Сетевая инфраструктура** | 8 500 000 | 1.6% |
| **Инфраструктура** (стойка/ИБП) | 1 500 000 | 0.3% |

### Детальная комплектация

**Compute-сервер SQL Server (4 шт) — 3 961 716 ₽/шт**


| Компонент | Цена | Кол-во | Источник |
| :-- | --: | --: | :-- |
| Intel Xeon Platinum 8480+ (56 cores) | 898 098 | 2 | digital-tex.ru [^13_1] |
| RAM 128GB DDR5 5600 Samsung ECC | 115 000 | 8 | Оценка |
| Samsung PM9A3 7.68TB (TempDB) | 134 880 | 4 | Secumarket [^13_2] |
| Mellanox CX-6 Dx 100GbE | 106 000 | 1 | 3logic.ru [^13_3] |
| Платформа 2U Dual Socket | 600 000 | 1 | Оценка |

**Storage-сервер SAN (10 шт) — 1 320 000 ₽/шт**


| Компонент | Цена | Кол-во | Источник |
| :-- | --: | --: | :-- |
| HDD 22TB SATA (WD/Seagate) | 47 000 | 12 | Regard [^13_4] |
| Enterprise RAID-контроллер | 150 000 | 1 | Оценка |
| Mellanox CX-6 Dx 100GbE | 106 000 | 1 | 3logic.ru [^13_3] |
| Платформа 2U 12LFF Storage | 500 000 | 1 | Оценка |

**Лицензии SQL Server Enterprise**

- Общее количество ядер: 4 сервера × 2 CPU × 56 cores = **448 ядер**
- Необходимо 2-core packs: **224 шт**
- Стоимость: 224 × 2 178 880 ₽ = **488 069 120 ₽**[^13_5]


### Сравнение архитектур

| Решение | Стоимость (₽) | Доля лицензий | Кратность |
| :-- | --: | --: | --: |
| **Data Lakehouse** (S3 + Iceberg + Spark) | 42 412 000 | 0% | 1.0× |
| **SQL Server DWH** (Compute + SAN) | 527 115 984 | 92.6% | **12.4×** |

### Ключевые выводы

1. **Архитектура стала реалистичнее**: Вместо 16 серверов SQL нужно всего 4 compute-сервера + 10 storage-серверов.
2. **Стоимость упала с 2 млрд до 527 млн** (в 4 раза дешевле первоначального расчета), но всё равно в **12.4 раза дороже** Data Lakehouse.
3. **Лицензии — это 92.6% бюджета** (почти полмиллиарда рублей). Железо стоит копейки по сравнению с ними.
4. Даже при "умной" архитектуре SQL Server остается экономически невыгодным решением для петабайтных хранилищ.
<span style="display:none">[^13_10][^13_11][^13_12][^13_13][^13_14][^13_15][^13_16][^13_17][^13_6][^13_7][^13_8][^13_9]</span>

<div align="center">⁂</div>

[^13_1]: https://digital-tex.ru/catalog/komplektuyushchie/komplektuyushchie_dlya_serverov/protsessory/protsessor_intel_xeon_platinum_8480_pk8071305074801srm7h/

[^13_2]: https://secumarket.ru/product/pm9a3-7-68tb-mzql27t6hbla-00a07-122584

[^13_3]: https://3logic.ru/products/mcx623106ac-cdat-connectx-6-dx-en-adapter-card-100gbe-dual-port-qsfp56-pcie-4-0-x16-crypto-and--90098/

[^13_4]: https://www.regard.ru/reciept/30948123/servernye-zestkie-diski-hdd-22-tb

[^13_5]: https://www.softmagazin.ru/microsoft/dg7gmgf0m7xv-0003/

[^13_6]: https://superfri.org/index.php/superfri/article/view/20

[^13_7]: https://www.dell.com/en-us/shop/storage-servers-and-networking-for-business/sf/unity-xt

[^13_8]: https://www.dell.com/en-in/shop/storage-servers-and-networking-for-business/sf/unity-xt

[^13_9]: https://www.serverbasket.net/c/servers/storage-servers/dell/unity-xt/

[^13_10]: https://www.gotomojo.com/wp-content/uploads/2019/09/Dell-EMC-Unity-XT-Series-Spec-Sheet.pdf

[^13_11]: https://www.gotomojo.com/storage/dell-emc/unity-xt/

[^13_12]: https://market.yandex.ru/search?text=Стоимость+схд+1+петабайт

[^13_13]: https://yadro.com/en/tatlin

[^13_14]: https://dell.adg.vn/product/dell-emc-unity-xt-storage-series/

[^13_15]: https://www.ozon.ru/category/zhestkiy-disk-1-petabayt/

[^13_16]: https://shop.nav-it.ru/catalogue/vneshnie_diskovye_massivy/sistema_khraneniya_yadro_tatlin_flex_one_x24_12x10tb_7_2k_3_5_sas_2x1_92tb_2_5_sas_25g_2p_y18sysbas1/

[^13_17]: https://www.dell.com/en-sg/shop/data-storage-and-backup/sc/storage-products/unity-xt

