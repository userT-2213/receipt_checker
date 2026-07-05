from datetime import date
import re
import cv2
import numpy as np
import easyocr


class ReceiptOCRService:
    def __init__(self):
        self.reader = easyocr.Reader(["ja", "en"], gpu=False)

    def analyze(self, image):
        processed_img = preprocess_image(image)
        ocr_results = self.reader.readtext(
            processed_img,
            detail=1,
            paragraph=False,
        )
        lines = make_lines(ocr_results)

        detected_date = extract_date(lines)
        detected_shop = extract_shop(lines)
        detected_items = extract_items(lines)
        detected_price = extract_total_amount(lines)
        detected_purpose = classify_purpose(detected_shop, detected_items)

        return {
            "processed_image": processed_img,
            "lines": lines,
            "date": detected_date,
            "shop": detected_shop,
            "items": detected_items,
            "amount": detected_price,
            "purpose": detected_purpose,
        }


def normalize_text(text):
    table = str.maketrans(
        "０１２３４５６７８９／－：￥，．ＯｏＩｌ",
        "0123456789/-:¥,.OoIl",
    )
    text = text.translate(table)
    text = text.replace(" ", "").strip()

    text = text.replace("1O%", "10%")
    text = text.replace("IO%", "10%")
    text = text.replace("I0%", "10%")
    text = text.replace("(1O%)", "(10%)")
    text = text.replace("(IO%)", "(10%)")
    text = text.replace("(I0%)", "(10%)")

    return text


def preprocess_image(image):
    image_rgb = image.convert("RGB")
    image_np = np.array(image_rgb)
    gray = cv2.cvtColor(image_np, cv2.COLOR_RGB2GRAY)

    h, w = gray.shape
    if max(h, w) < 1400:
        scale = 1400 / max(h, w)
        gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)

    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    gray = clahe.apply(gray)
    gray = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)

    return cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        11,
    )


def make_lines(ocr_results):
    boxes = []

    for box, text, conf in ocr_results:
        if not text or conf < 0.25:
            continue

        xs = [p[0] for p in box]
        ys = [p[1] for p in box]

        boxes.append({
            "text": text.strip(),
            "conf": conf,
            "x1": min(xs),
            "x2": max(xs),
            "y1": min(ys),
            "y2": max(ys),
            "yc": sum(ys) / len(ys),
        })

    boxes.sort(key=lambda b: (b["yc"], b["x1"]))

    lines = []
    for b in boxes:
        placed = False

        for line in lines:
            line_height = max(10, line["y2"] - line["y1"])

            if abs(b["yc"] - line["yc"]) <= line_height * 0.6:
                line["parts"].append(b)
                line["x1"] = min(line["x1"], b["x1"])
                line["x2"] = max(line["x2"], b["x2"])
                line["y1"] = min(line["y1"], b["y1"])
                line["y2"] = max(line["y2"], b["y2"])
                line["yc"] = (line["yc"] + b["yc"]) / 2
                placed = True
                break

        if not placed:
            lines.append({
                "parts": [b],
                "x1": b["x1"],
                "x2": b["x2"],
                "y1": b["y1"],
                "y2": b["y2"],
                "yc": b["yc"],
            })

    formatted = []

    for line in lines:
        parts = sorted(line["parts"], key=lambda p: p["x1"])
        text = " ".join(p["text"] for p in parts)

        formatted.append({
            "text": text,
            "clean": normalize_text(text),
            "x1": line["x1"],
            "x2": line["x2"],
            "y1": line["y1"],
            "y2": line["y2"],
            "yc": line["yc"],
        })

    return formatted


def is_date_or_phone(text):
    text = normalize_text(text)

    if re.search(r"20\d{2}[年/-]\d{1,2}[月/-]\d{1,2}", text):
        return True
    if re.search(r"\d{2,4}-\d{2,4}-\d{3,4}", text):
        return True
    if re.search(r"0\d{1,4}[-ー−]\d{1,4}[-ー−]\d{3,4}", text):
        return True

    return False


def is_address_line(text):
    text = normalize_text(text)

    address_words = [
        "都", "道", "府", "県", "市", "区", "町", "村",
        "丁目", "番地", "番", "号",
    ]

    if any(w in text for w in address_words) and re.search(r"\d", text):
        return True

    if re.search(r"\d+-\d+", text) and any(w in text for w in address_words):
        return True

    return False


def extract_date(lines):
    date_patterns = [
        r"(20\d{2})年\s*(\d{1,2})月\s*(\d{1,2})日?",
        r"(20\d{2})[/-](\d{1,2})[/-](\d{1,2})",
        r"(\d{2})[/-](\d{1,2})[/-](\d{1,2})",
    ]

    for line in lines:
        clean_text = normalize_text(line["text"])

        if re.search(r"\d{2,4}-\d{2,4}-\d{3,4}", clean_text):
            continue

        for pattern in date_patterns:
            m = re.search(pattern, clean_text)
            if m:
                y, mo, d = m.groups()
                if len(y) == 2:
                    y = "20" + y

                try:
                    return f"{int(y):04d}-{int(mo):02d}-{int(d):02d}"
                except ValueError:
                    pass

    joined_text = normalize_text("".join(line["text"] for line in lines))

    for pattern in date_patterns:
        m = re.search(pattern, joined_text)
        if m:
            y, mo, d = m.groups()
            if len(y) == 2:
                y = "20" + y

            try:
                return f"{int(y):04d}-{int(mo):02d}-{int(d):02d}"
            except ValueError:
                pass

    return str(date.today())


def extract_amounts(text):
    text = normalize_text(text)

    candidates = re.findall(
        r"(?:¥|￥)?([0-9]{1,3}(?:,[0-9]{3})+|[0-9]{2,6})円?",
        text,
    )

    amounts = []

    for c in candidates:
        value = int(c.replace(",", ""))

        if value == 10 and "%" in text:
            continue

        if 1 <= value <= 999999:
            amounts.append(value)

    return amounts


def fix_amount_misread(amount, text):
    clean = normalize_text(text)

    if "税込(10%)" in clean and 1000 <= amount <= 1999:
        corrected = amount - 1000
        if corrected >= 100:
            return corrected

    if any(k in clean for k in ["小計", "合計", "総合計", "税込合計"]) and 1000 <= amount <= 1999:
        corrected = amount - 1000
        if corrected >= 100:
            return corrected

    return amount


def extract_total_amount(lines):
    total_keywords = [
        "合計", "総合計", "税込合計", "お買上合計", "お買い上げ合計",
        "ご請求", "請求金額", "現計", "売上", "支払",
    ]

    subtotal_keywords = ["小計"]

    exclude_keywords = [
        "お預", "預り", "お釣", "釣銭", "ポイント", "残高",
        "税率", "対象", "内税", "外税", "電話", "TEL", "登録番号", "レジ",
    ]

    scored = []

    for idx, line in enumerate(lines):
        text = line["clean"]

        if is_date_or_phone(text):
            continue

        if any(k in text for k in exclude_keywords):
            continue

        amounts = extract_amounts(text)

        if any(k in text for k in total_keywords) and not amounts:
            if idx + 1 < len(lines):
                next_text = lines[idx + 1]["clean"]

                if not any(k in next_text for k in exclude_keywords):
                    next_amounts = extract_amounts(next_text)

                    for amount in next_amounts:
                        fixed_amount = fix_amount_misread(amount, text + next_text)
                        scored.append((150 + idx, fixed_amount))

        if not amounts:
            continue

        score = idx

        if any(k in text for k in total_keywords):
            score += 120

        if any(k in text for k in subtotal_keywords):
            score += 80

        for amount in amounts:
            fixed_amount = fix_amount_misread(amount, text)
            scored.append((score, fixed_amount))

    if scored:
        scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
        return scored[0][1]

    usable_amounts = []

    for line in lines:
        text = line["clean"]

        if is_date_or_phone(text):
            continue

        if any(k in text for k in exclude_keywords):
            continue

        for amount in extract_amounts(text):
            usable_amounts.append(fix_amount_misread(amount, text))

    return max(usable_amounts) if usable_amounts else 0


def looks_like_shop_line(text):
    text = normalize_text(text)

    if len(text) < 2:
        return False

    ng_words = [
        "領収書", "レシート", "明細", "登録番号", "電話", "TEL",
        "担当", "責任者", "レジ", "日時", "合計", "小計", "税",
        "お預", "お釣", "ポイント", "クレジット", "現金",
    ]

    if any(w in text for w in ng_words):
        return False

    if is_address_line(text):
        return False

    if is_date_or_phone(text):
        return False

    if extract_amounts(text):
        return False

    digit_count = len(re.findall(r"\d", text))
    if digit_count >= len(text) * 0.3:
        return False

    return True


def extract_shop(lines):
    if not lines:
        return ""

    max_y = max(line["y2"] for line in lines)
    top_lines = [line for line in lines if line["yc"] <= max_y * 0.45]

    shop_lines = []

    for line in top_lines:
        text = line["text"].strip()
        clean = line["clean"]

        if is_address_line(clean) or is_date_or_phone(clean):
            if shop_lines:
                break
            continue

        if looks_like_shop_line(clean):
            shop_lines.append(text)
        elif shop_lines:
            break

    if shop_lines:
        return " ".join(shop_lines).strip()

    return ""


def is_receipt_noise_line(text):
    text = normalize_text(text)

    noise_keywords = [
        "領収", "収書", "領収書", "領収証", "レシート", "明細", "納品書",
        "店名", "店舗", "支店", "営業所",
        "電話", "TEL", "Tel", "tel", "FAX",
        "住所", "郵便", "〒",
        "登録番号", "インボイス", "事業者",
        "レジ", "担当", "責任者", "係", "No", "NO", "番号",
        "取引", "伝票", "会計", "精算",
        "日付", "日時", "時刻",
        "小計", "合計", "総合計", "税込合計", "税抜合計",
        "内税", "外税", "消費税", "税率", "対象", "課税", "非課税",
        "軽減税率", "税込", "税抜",
        "お預", "預り", "お釣", "釣銭", "現金", "クレジット",
        "カード", "電子マネー", "PayPay", "Suica", "PASMO",
        "ポイント", "残高", "今回", "累計",
        "お買上", "お買い上げ", "ありがとうございました",
        "またお越し", "ご利用", "返品", "交換",
    ]

    if any(k in text for k in noise_keywords):
        return True

    if is_date_or_phone(text):
        return True

    if is_address_line(text):
        return True

    if re.fullmatch(r"[¥￥]?[0-9,]+円?", text):
        return True

    if re.fullmatch(r"[0-9\-:./]+", text):
        return True

    if re.fullmatch(r"\(?[0-9]{1,2}%\)?", text):
        return True

    return False


def clean_item_name(text):
    text = normalize_text(text)

    text = re.sub(r"^[*＊※・\-\s]+", "", text)
    text = re.sub(r"(?:¥|￥)?[0-9]{1,3}(?:,[0-9]{3})+円?$", "", text)
    text = re.sub(r"(?:¥|￥)?[0-9]{2,6}円?$", "", text)
    text = re.sub(r"[x×メ]\d+.*$", "", text)
    text = re.sub(r"\d+点.*$", "", text)

    text = text.replace("ルン", "パン")
    text = text.replace("パソ", "パン")

    return text.strip(" -:：税込軽減*＊")


def is_valid_item_name(item):
    item = normalize_text(item)

    if len(item) < 2:
        return False

    if is_receipt_noise_line(item):
        return False

    shop_like_words = [
        "店", "支店", "営業所", "株式会社", "有限会社",
        "スーパー", "ストア", "マート", "コンビニ",
    ]

    if any(k in item for k in shop_like_words) and len(item) <= 15:
        return False

    digit_count = len(re.findall(r"\d", item))
    if digit_count >= len(item) * 0.4:
        return False

    symbol_removed = re.sub(r"[0-9A-Za-z¥￥,.\-/:()（）%#]", "", item)
    if len(symbol_removed) < 2:
        return False

    return True


def extract_items(lines):
    if not lines:
        return []

    total_stop_words = [
        "小計", "合計", "総合計", "税込合計", "税抜", "消費税", "内税",
        "外税", "お預", "預り", "お釣", "釣銭", "ポイント", "現金",
        "クレジット", "電子マネー", "登録番号",
    ]

    header_words = [
        "領収", "領収書", "領収証", "品名", "商品", "明細",
    ]

    end_idx = len(lines)

    for i, line in enumerate(lines):
        text = line["clean"]
        if any(k in text for k in total_stop_words):
            end_idx = i
            break

    start_idx = None

    for i, line in enumerate(lines[:end_idx]):
        text = line["clean"]

        if any(k in text for k in header_words):
            start_idx = i + 1
            break

    if start_idx is None:
        for i, line in enumerate(lines[:end_idx]):
            text = line["clean"]

            if is_receipt_noise_line(text):
                continue

            if not extract_amounts(text):
                continue

            item_candidate = clean_item_name(line["text"])

            if is_valid_item_name(item_candidate):
                start_idx = i
                break

    if start_idx is None:
        return []

    items = []

    for line in lines[start_idx:end_idx]:
        raw = line["text"]
        clean = line["clean"]

        if is_receipt_noise_line(clean):
            continue

        if not extract_amounts(clean):
            continue

        item = clean_item_name(raw)

        if not is_valid_item_name(item):
            continue

        if item not in items:
            items.append(item)

    return items


def classify_purpose(shop, items):
    text = normalize_text(shop + " " + " ".join(items))

    rules = {
        "食費": [
            "スーパー", "食品", "弁当", "パン", "牛乳", "野菜",
            "肉", "魚", "惣菜", "レストラン", "カフェ",
            "中華", "チキン", "おにぎり", "飲料", "茶", "水",
        ],
        "日用品": [
            "ドラッグ", "薬局", "洗剤", "ティッシュ",
            "トイレット", "シャンプー", "歯ブラシ", "石鹸",
        ],
        "交通費": ["交通", "鉄道", "バス", "タクシー", "運賃", "IC"],
        "衣服": ["ユニクロ", "GU", "衣料", "服", "靴"],
        "娯楽": ["映画", "カラオケ", "ゲーム", "書店", "本"],
        "医療": ["病院", "クリニック", "薬"],
    }

    for purpose, keywords in rules.items():
        if any(k in text for k in keywords):
            return purpose

    return "その他"