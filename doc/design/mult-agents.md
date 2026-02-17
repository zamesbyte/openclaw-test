这个场景设计旨在展示 OpenClaw 在**信息检索（Search）**、**浏览器自动化（Browser Automation）**和**本地文件管理（File Management）**之间的无缝协作。

我们把这个场景命名为：**“全网比价与口碑避雷助手” (The Smart Shopper Protocol)**。

### 场景背景

你种草了一款昂贵的数码产品（比如“Sony WH-1000XM5 耳机”），但你不想做“大冤种”。你需要知道哪个电商平台现在最便宜，并且必须确认这个低价店铺没有“发二手/假货”的黑历史。

---

### 1. Agent 角色设计 (The Team)

我们需要三个性格迥异的 Agent，分别负责“广撒网”、“查案底”和“写报告”。

#### **Agent A: 赏金猎人 (The Hunter)**

* **核心职责**：**浏览器操作（Browser Use）**。负责去各大电商网站“爬”价格。
* **技能配置**：`browser-use` (或 `puppeteer`), `vision` (可选，用于识别复杂的网页布局)。
* **性格设定**：行动派，只看数字，不负责判断真假。
* **任务**：打开 Amazon、BestBuy、eBay（或京东、淘宝网页版），搜索指定商品，提取前 3 个最低价的**链接**、**价格**和**店铺名称**。

#### **Agent B: 鉴谎师 (The Skeptic)**

* **核心职责**：**深度搜索与推理 (Deep Search & Reasoning)**。负责“泼冷水”。
* **技能配置**：`tavily-search` (或 `google-search`), `scrape-text`。
* **性格设定**：多疑，喜欢去 Reddit、什么值得买、贴吧等论坛挖掘黑料。
* **任务**：拿着 Agent A 提供的“店铺名称”或“超低价链接”，去搜索社区评价。比如搜索“XX店铺 假货”、“XX店铺 售后拒保”。如果发现负面评价超过阈值，直接打上“高风险”标签。

#### **Agent C: 审计员 (The Auditor)**

* **核心职责**：**数据汇总与文件归档 (File I/O)**。
* **技能配置**：`local-file-system`, `python-interpreter` (用于处理数据格式)。
* **性格设定**：严谨，喜欢做表格。
* **任务**：接收 A 的价格和 B 的风险评估，计算“性价比得分”，将最终的推荐结果生成为一个 Markdown 表格文件，保存在桌面上。

---

### 2. 交互细节与工作流 (The Workflow)

#### **步骤 0: 用户触发**

**User**: “OpenClaw，我想买一台 ‘Sony WH-1000XM5’ 黑色款。帮我看看 Amazon 和 eBay 上现在的最低价是多少，一定要帮我检查一下店铺靠不靠谱，别让我买到翻新机。最后给我个报告。”

#### **步骤 1: 赏金猎人 (Agent A) 出动**

* **思考/行动**：
1. 启动浏览器，访问 `amazon.com`。
2. 输入 “Sony WH-1000XM5 Black”。
3. 截图或抓取 HTML，找到 Amazon Warehouse 或第三方卖家的最低价（例如 $248）。
4. 访问 `ebay.com`，筛选 “Buy It Now” 和 “New”，找到最低价（例如 $220）。
5. **输出数据**：
```json
[
  {"source": "Amazon", "price": 248, "seller": "TechDeals_USA", "link": "http://amzn..."},
  {"source": "eBay", "price": 220, "seller": "QuickShip_99", "link": "http://ebay..."}
]

```




* **Handoff (对话移交)**：
> “@Skeptic，我找到了两个低价源。eBay 的价格很诱人，只有 220 刀，但卖家叫 'QuickShip_99'。Amazon 的是 248 刀。请你去核查一下这两个卖家的信誉。”



#### **步骤 2: 鉴谎师 (Agent B) 介入**

* **思考/行动**：
1. 调用 `tavily-search` 查询 "QuickShip_99 eBay scam reddit" 或 "QuickShip_99 review"。
2. 发现搜索结果显示：“User report: QuickShip_99 sent me a used item listed as new” (用户举报发二手)。 -> **标记风险：高**。
3. 查询 "TechDeals_USA reviews"。结果显示多为正面，是授权经销商。 -> **标记风险：低**。


* **Handoff (对话移交)**：
> “@Auditor，查验完毕。eBay 的 $220 选项是陷阱，存在‘以旧充新’的高风险。Amazon 的 $248 选项安全。请汇总报告。”



#### **步骤 3: 审计员 (Agent C) 收尾**

* **思考/行动**：
1. 调用 `python` 格式化数据。
2. 创建一个 Markdown 内容：
```markdown
# 购物决策建议：Sony WH-1000XM5
| 平台 | 价格 | 卖家 | 风险等级 | 建议 |
|---|---|---|---|---|
| eBay | $220 | QuickShip_99 | 🔴 高 (疑似二手) | **绝对不要买** |
| Amazon| $248 | TechDeals_USA | 🟢 低 | **推荐购买** |

**结论**：多花 $28 买 Amazon 的，因为 eBay 卖家有翻新机黑历史。

```


3. 调用 `write_file` 将其保存到 `/Users/Desktop/buying_guide.md`。


* **最终回复**：
> “报告已生成在您的桌面 `buying_guide.md`。结论是：别贪便宜买 eBay 那家，去买 Amazon 的。”



---

### 3. OpenClaw 实现提示 (Pro Tips)

在 OpenClaw 中配置这个场景时，有几个关键点可以让效果更“炸裂”：

1. **System Prompt 隔离**：
* 给 **Agent A** 的 Prompt 强调：“你是一个无情的爬虫，不要关心评论，只关心价格数字和 URL。”
* 给 **Agent B** 的 Prompt 强调：“你是一个偏执的侦探，你的目标是找到一切可能的负面新闻。如果没有负面新闻，才能放行。”


2. **Browser 的可视化**：
* 在演示时，让 Agent A 的浏览器窗口设为 `headless: false`（非无头模式）。这样用户能看到浏览器自己打开、输入、滚动的过程，这是“多 Agent 协作”中最具视觉冲击力的一环。


3. **错误处理**：
* 在 Agent A 中设置重试机制。如果电商网站弹出“验证码”，Agent A 应该能识别并求助（或者尝试刷新），而不是卡死。



### 4. 为什么这个设计比“订机票”好？

* **冲突与博弈**：Agent A 追求“低价”，Agent B 追求“安全”。这种**内在冲突（Conflict）需要 Agent C 来仲裁，这体现了多 Agent 系统的真正的智能——不仅仅是执行命令，而是进行多维度的权衡（Trade-off）**。这在展示 OpenClaw 的推理能力时非常加分。