import datetime
import re
import cv2
import os
import csv
import numpy as np
import pandas as pd
import easyocr
from PIL import Image
import io

# FastAPIのインポート
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="ReceiptTracker API")

# スマホアプリ（ローカル接続等）からの通信を許可するCORS設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_headers=["*"],
    allow_methods=["*"],
)

# --- 1. OCRリーダーの初期化 ---
reader = easyocr.Reader(['ja', 'en'])
FILE_PATH = "expenses.csv"

# 初期ファイル作成
if not os.path.exists(FILE_PATH):
    with open(FILE_PATH, mode='w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["日付", "店名", "商品名", "金額", "カテゴリ"])

# --- 2. 既存のロジッククラスの流用（st. の依存を排除） ---

class OpenCVHandler:
    def preprocess_image(self, image_pil: Image.Image) -> np.ndarray:
        image_cv = cv2.cvtColor(np.array(image_pil), cv2.COLOR_RGB2BGR)
        gray = cv2.cvtColor(image_cv, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
        binary_image = cv2.adaptiveThreshold(
            resized, 255, 
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY, 
            15, 3
        )
        return binary_image

class ReceiptProcessor:
    def __init__(self):
        self.open_cv_handler = OpenCVHandler()

    def extract_expense_from_image(self, image_pil: Image.Image):
        processed_image_np = self.open_cv_handler.preprocess_image(image_pil)
        results = reader.readtext(processed_image_np, detail=0)
        
        detected_date = str(datetime.date.today())
        detected_shop = ""
        detected_price = 0
        detected_items = []
        
        base_shop_name = ""
        branch_name = ""
        
        for i, text in enumerate(results[:7]):
            text_clean = text.strip()
            if len(text_clean) <= 1: continue
            if re.search(r'\d{4}[年\-/]|\d{1,2}[月\-/]', text_clean): continue
            if re.search(r'TEL|tel|0\d{1,4}-\d{1,4}-\d{3,4}', text_clean): continue
            if re.search(r'領収|レシート|登録|番号', text_clean): continue
            if re.search(r'[xXメ*✕]\s*\d+|\d+円|￥', text_clean): continue
            
            text_clean = text_clean.replace("ナインイレナン", "ナインイレブン").replace("ナインイレプン", "ナインイレブン")
            base_shop_name = text_clean
            
            if "店" in text_clean and len(text_clean) > 3:
                break
            elif i + 1 < len(results[:8]):
                next_text = results[i+1].strip()
                if "店" in next_text and not re.search(r'\d+円|TEL', next_text):
                    branch_name = next_text
                break

        if base_shop_name:
            if branch_name and branch_name not in base_shop_name:
                detected_shop = f"{base_shop_name} {branch_name}"
            else:
                detected_shop = base_shop_name

        for text in results:
            text = text.replace("ナインイレナン", "ナインイレブン").replace("ナインイレプン", "ナインイレブン")
            item_match = re.search(r'(.+?)\s*[xXメ*✕]\s*\d+', text)
            if item_match:
                product_name = item_match.group(1).strip()
                if not any(noise in product_name for noise in ["責", "：", ":"]):
                    if re.search(r'[^\d\W]', product_name):
                        detected_items.append(product_name)

            date_match = re.search(r'(\d{4})\s*[年\-/]\s*(\d{1,2})\s*[月\-/]\s*(\d{1,2})', text)
            if date_match:
                year, month, day = date_match.groups()
                detected_date = f"{int(year):04d}-{int(month):02d}-{int(day):02d}"

            if "計" in text:
                numbers = re.findall(r'\d+', text)
                if numbers:
                    try: detected_price = int(numbers[-1])
                    except: pass

        if detected_price == 0:
            for text in results:
                clean_text = re.sub(r'[^\d]', '', text)
                if clean_text.isdigit() and 2 <= len(clean_text) <= 6:
                    detected_price = int(clean_text)
                    
        formatted_items = "\n".join(detected_items)
        if not detected_shop and len(results) > 0:
            detected_shop = results[0]
                    
        return {
            "date": detected_date,
            "store": detected_shop,
            "item": formatted_items,
            "amount": detected_price,
            "category": "食費"
        }

# --- 3. スマホからのリクエストを受け付ける API エンドポイント ---

class ExpenseModel(BaseModel):
    date: str
    store: str
    item: str
    amount: int
    category: str

@app.post("/api/ocr")
async def run_ocr(file: UploadFile = File(...)):
    """スマホで撮影・アップロードした画像を解析するAPI"""
    try:
        image_bytes = await file.read()
        image_pil = Image.open(io.BytesIO(image_bytes))
        
        processor = ReceiptProcessor()
        draft_result = processor.extract_expense_from_image(image_pil)
        return draft_result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/expenses")
async def save_expense(expense: ExpenseModel):
    """スマホで確認・修正されたデータをCSVに保存するAPI"""
    try:
        with open(FILE_PATH, mode='a', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([expense.date, expense.store, expense.item, expense.amount, expense.category])
        return {"status": "success", "message": "データを保存しました"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/expenses")
async def get_expenses():
    """CSVから全データを取得してスマホに返すAPI（ダッシュボード・履歴用）"""
    if not os.path.exists(FILE_PATH):
        return []
    df = pd.read_csv(FILE_PATH, encoding='utf-8')
    # JSON化しやすい辞書配列の形式に変換して返却
    return df.to_dict(orient="records")