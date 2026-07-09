import streamlit as st
from PIL import Image
import easyocr
import numpy as np
import datetime
import re
import cv2
import os
import csv
import pandas as pd
import plotly.express as px
import calendar
import locale

# ページの初期設定（最優先で実行）
st.set_page_config(layout="wide", page_title="スマート・レシート・チェッカー")

# 曜日や月選択のカレンダー表示を日本語化するためのロケール設定
try:
    locale.setlocale(locale.LC_ALL, 'ja_JP.UTF-8')
except Exception:
    try:
        locale.setlocale(locale.LC_ALL, 'japanese')
    except Exception:
        pass  # サーバー環境によって適用できない場合のフォールバック

# --- 1. AIモデル（OCRリーダー）の初期化 ---
@st.cache_resource
def load_ocr_reader():
    return easyocr.Reader(['ja', 'en'])

reader = load_ocr_reader()

# --- 2. ドメイン・データ管理クラスの定義 ---

class OpenCVHandler:
    """OpenCVによる画像前処理を担当するクラス"""
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
        st.session_state.preprocessed_image = binary_image
        return binary_image

class ExpenseDraft:
    """OCR解析直後の下書きデータを保持するクラス"""
    def __init__(self, date: str, store: str, item: str, amount: int, category: str):
        self.date = date
        self.store = store
        self.item = item
        self.amount = amount
        self.category = category

class CSVDataManager:
    """データの永続化（CSV保存・読込）を担当するクラス"""
    def __init__(self, file_path="expenses.csv"):
        self.file_path = file_path
        if not os.path.exists(self.file_path):
            self.clear_and_create_file()

    def clear_and_create_file(self):
        with open(self.file_path, mode='w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["日付", "店名", "商品名", "金額", "カテゴリ"])

    def save_expense(self, date: str, store: str, item: str, amount: int, category: str) -> bool:
        try:
            with open(self.file_path, mode='a', encoding='utf-8', newline='') as f:
                writer = csv.writer(f)
                writer.writerow([date, store, item, amount, category])
            return True
        except Exception as e:
            st.error(f"データの保存中にエラーが発生しました: {e}")
            return False

    def load_all_expenses(self):
        if not os.path.exists(self.file_path):
            return pd.DataFrame(columns=["日付", "店名", "商品名", "金額", "カテゴリ"])
        try:
            df = pd.read_csv(self.file_path, encoding='utf-8')
            df["日付"] = pd.to_datetime(df["日付"])
            return df
        except Exception:
            return pd.DataFrame(columns=["日付", "店名", "商品名", "金額", "カテゴリ"])

    def delete_expenses_by_indices(self, indices_to_delete) -> bool:
        try:
            df = self.load_all_expenses()
            df_remaining = df.drop(indices_to_delete)
            
            with open(self.file_path, mode='w', encoding='utf-8', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(["日付", "店名", "商品名", "金額", "カテゴリ"])
                for _, row in df_remaining.iterrows():
                    date_str = row["日付"].strftime('%Y-%m-%d')
                    writer.writerow([date_str, row["店名"], row["商品名"], row["金額"], row["カテゴリ"]])
            return True
        except Exception as e:
            st.error(f"データの削除中にエラーが発生しました: {e}")
            return False

class ReceiptProcessor:
    """レシート画像の解析を統括するクラス"""
    def __init__(self):
        self.open_cv_handler = OpenCVHandler()

    def extract_expense_from_image(self, image_pil: Image.Image) -> ExpenseDraft:
        processed_image_np = self.open_cv_handler.preprocess_image(image_pil)
        results = reader.readtext(processed_image_np, detail=0)
        st.session_state.raw_ocr_results = results
        
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

        for i, text in enumerate(results):
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
                    try:
                        detected_price = int(numbers[-1])
                    except:
                        pass

        if detected_price == 0:
            for text in results:
                clean_text = re.sub(r'[^\d]', '', text)
                if clean_text.isdigit() and 2 <= len(clean_text) <= 6:
                    detected_price = int(clean_text)
                    
        formatted_items = "\n".join(detected_items)
        if not detected_shop and len(results) > 0:
            detected_shop = results[0]
                    
        return ExpenseDraft(
            date=detected_date, store=detected_shop, item=formatted_items, amount=detected_price, category="食費"
        )

# --- 3. アプリケーションUI補助関数 ---

def get_week_number(dt):
    """日付から第何週かを判定する補助関数"""
    day = dt.day
    if day <= 7: return 1
    elif day <= 14: return 2
    elif day <= 21: return 3
    elif day <= 28: return 4
    else: return 5

# --- 4. メインアプリケーション ---

def main():
    st.title("支出管理アプリ（スマート・レシート・チェッカー）")
    st.write("---")

    data_manager = CSVDataManager()

    categories = [
        "食費", "趣味", "交通費", "日用品", "教育", 
        "水道・光熱費", "家賃", "保険", "通信費", "美容・衣服", "医療・健康", "その他"
    ]
    
    category_color_map = {
        "食費": "#FFA6A6", "趣味": "#FFCFA6", "交通費": "#FFFF00", "日用品": "#A6FFA6", 
        "教育": "#B3F0FF", "水道・光熱費": "#A6C8FF", "家賃": "#D9B3FF", "保険": "#FFCCE6", 
        "通信費": "#FFA6FF", "美容・衣服": "#7CA48D", "医療・健康": "#D3D3D3", "その他": "#85DFB3"        
    }
    fallback_color = "#A1E7D1"    

    # セッション状態の初期化
    today = datetime.date.today()
    if "sync_year" not in st.session_state:
        st.session_state.sync_year = today.year
    if "sync_month" not in st.session_state:
        st.session_state.sync_month = today.month
    if "sync_week" not in st.session_state:
        st.session_state.sync_week = get_week_number(today)
    if "sync_scope" not in st.session_state:
        st.session_state.sync_scope = "週単位"
    if "pie_scope_selection" not in st.session_state:
        st.session_state.pie_scope_selection = "月単位"

    if "expense_draft" not in st.session_state:
        st.session_state.expense_draft = None
    if "raw_ocr_results" not in st.session_state:
        st.session_state.raw_ocr_results = []
    if "preprocessed_image" not in st.session_state:
        st.session_state.preprocessed_image = None
    if "last_uploaded_file" not in st.session_state:
        st.session_state.last_uploaded_file = None
    if "delete_mode" not in st.session_state:
        st.session_state.delete_mode = False

    tab_input, tab_dashboard = st.tabs(["📥 レシート登録・入力", "📊 支出集計ダッシュボード"])

    # ==========================================
    # タブ1: レシート登録・入力
    # ==========================================
    with tab_input:
        st.header("1. レシート画像のアップロード")
        uploaded_file = st.file_uploader("レシート画像をアップロードしてください", type=["png", "jpg", "jpeg"])

        if uploaded_file is not None and uploaded_file != st.session_state.last_uploaded_file:
            st.session_state.last_uploaded_file = uploaded_file
            image = Image.open(uploaded_file)
            with st.spinner("OpenCV前処理 ＆ AI文字解析を実行中..."):
                processor = ReceiptProcessor()
                st.session_state.expense_draft = processor.extract_expense_from_image(image)
            st.success("解析が完了しました！")

        if uploaded_file is not None:
            col1, col2 = st.columns(2)
            with col1:
                st.image(Image.open(uploaded_file), caption="元のアップロード画像", use_column_width=True)
            with col2:
                if st.session_state.preprocessed_image is not None:
                    st.image(st.session_state.preprocessed_image, caption="OpenCV二値化後の画像", use_column_width=True)

        st.header("2. 支出情報の入力・確認")
        draft = st.session_state.expense_draft
        init_date = datetime.datetime.strptime(draft.date, "%Y-%m-%d").date() if draft else datetime.date.today()
        init_store = draft.store if draft else ""
        init_item = draft.item if draft else ""
        init_amount = draft.amount if draft else 0
        init_category = draft.category if draft else "食費"

        try:
            category_index = categories.index(init_category)
        except ValueError:
            category_index = 0

        with st.form(key="expense_form"):
            input_date = st.date_input("日付", value=init_date)
            input_store = st.text_input("店名", value=init_store)
            input_item = st.text_area("商品名（改行可）", value=init_item, height=100)
            input_amount = st.number_input("金額 (円)", min_value=0, value=init_amount, step=1)
            input_category = st.selectbox("カテゴリ", options=categories, index=category_index)
            
            if st.form_submit_button(label="データを保存する"):
                if not input_store.strip() or not input_item.strip() or input_amount <= 0:
                    st.error("入力内容に不備があります。")
                else:
                    if data_manager.save_expense(str(input_date), input_store, input_item, input_amount, input_category):
                        st.success("データを保存しました！")
                        st.session_state.expense_draft = None
                        st.rerun()

        st.header("3. 登録データ履歴")
        raw_df = data_manager.load_all_expenses()
        
        if not raw_df.empty:
            h_col1, h_col2, h_col3, h_col4 = st.columns([2, 1, 1, 1])
            with h_col2:
                sort_target = st.selectbox("並び替え項目", options=["新しい順", "金額順", "日付順"], label_visibility="collapsed")
            with h_col3:
                sort_order = st.selectbox("順序", options=["降順", "昇順"], label_visibility="collapsed")
            with h_col4:
                if not st.session_state.delete_mode:
                    if st.button("🗑 データを削除する", key="btn_del_start", type="primary", use_container_width=True):
                        st.session_state.delete_mode = True
                        st.rerun()
                else:
                    b_col1, b_col2 = st.columns([1, 1])
                    with b_col1:
                        confirm_delete = st.button("🔴 削除", key="btn_del_confirm", type="primary", use_container_width=True)
                    with b_col2:
                        if st.button("❌ 戻る", key="btn_del_cancel", use_container_width=True):
                            st.session_state.delete_mode = False
                            st.rerun()

            is_ascending = (sort_order == "昇順")
            processed_df = raw_df.copy().reset_index()
            if sort_target == "新しい順":
                processed_df = processed_df.sort_values(by="index", ascending=is_ascending)
            elif sort_target == "金額順":
                processed_df = processed_df.sort_values(by="金額", ascending=is_ascending)
            elif sort_target == "日付順":
                processed_df = processed_df.sort_values(by=["日付", "index"], ascending=[is_ascending, is_ascending])

            processed_df["日付"] = processed_df["日付"].dt.strftime('%Y-%m-%d')

            if st.session_state.delete_mode:
                st.warning("⚠️ 削除したい項目にチェックを入れ、右上の「🔴 削除」ボタンを押してください。")
                processed_df.insert(0, "選択", False)
                edited_df = st.data_editor(
                    processed_df,
                    column_config={"選択": st.column_config.CheckboxColumn("選択", default=False), "index": None},
                    disabled=["日付", "店名", "商品名", "金額", "カテゴリ"],
                    use_container_width=True, key="delete_data_editor"
                )
                selected_indices = edited_df[edited_df["選択"] == True]["index"].tolist()
                if 'confirm_delete' in locals() and confirm_delete:
                    if not selected_indices:
                        st.error("削除する項目が選択されていません。")
                    else:
                        if data_manager.delete_expenses_by_indices(selected_indices):
                            st.success(f"{len(selected_indices)}件のデータを削除しました。")
                            st.session_state.delete_mode = False
                            st.rerun()
            else:
                st.dataframe(processed_df.drop(columns=["index"]), use_container_width=True)
        else:
            st.info("データがありません。")

    # ==========================================
    # タブ2: 支出集計ダッシュボード
    # ==========================================
    with tab_dashboard:
        st.header("📊 期間別集計・可視化")
        df = data_manager.load_all_expenses()

        if df.empty:
            st.info("集計するデータがまだありません。")
        else:
            years_options = list(range(today.year - 5, today.year + 6))
            months_options = [f"{i}月" for i in range(1, 13)]
            weeks_options = [f"第{i}週" for i in range(1, 6)]

            def on_period_scope_change():
                st.session_state.sync_scope = st.session_state.dashboard_period_scope
                if st.session_state.sync_scope in ["週単位", "月単位"]:
                    st.session_state.pie_scope_selection = "月単位"
                else:
                    st.session_state.pie_scope_selection = "年単位"

            c_sel1, c_sel2, c_sel3, c_sel4 = st.columns([2, 1, 1, 1])
            with c_sel1:
                st.radio(
                    "表示範囲を選択してください:", options=["週単位", "月単位", "年単位"], horizontal=True,
                    index=["週単位", "月単位", "年単位"].index(st.session_state.sync_scope),
                    key="dashboard_period_scope", on_change=on_period_scope_change
                )
            with c_sel2:
                st.selectbox(
                    "年", options=years_options, index=years_options.index(st.session_state.sync_year), key="sum_select_year",
                    on_change=lambda: setattr(st.session_state, "sync_year", st.session_state.sum_select_year)
                )
            with c_sel3:
                st.selectbox(
                    "月", options=months_options, index=st.session_state.sync_month - 1, disabled=(st.session_state.sync_scope == "年単位"), key="sum_select_month",
                    on_change=lambda: setattr(st.session_state, "sync_month", months_options.index(st.session_state.sum_select_month) + 1)
                )
            with c_sel4:
                st.selectbox(
                    "週", options=weeks_options, index=st.session_state.sync_week - 1, disabled=(st.session_state.sync_scope in ["月単位", "年単位"]), key="sum_select_week",
                    on_change=lambda: setattr(st.session_state, "sync_week", weeks_options.index(st.session_state.sum_select_week) + 1)
                )

            # データフィルタリング
            df_sum_filtered = df.copy()
            df_sum_filtered["year_num"] = df_sum_filtered["日付"].dt.year
            df_sum_filtered["month_num"] = df_sum_filtered["日付"].dt.month
            df_sum_filtered["week_num"] = df_sum_filtered["日付"].apply(get_week_number)

            if st.session_state.sync_scope == "週単位":
                target_period_df = df_sum_filtered[
                    (df_sum_filtered["year_num"] == st.session_state.sync_year) &
                    (df_sum_filtered["month_num"] == st.session_state.sync_month) &
                    (df_sum_filtered["week_num"] == st.session_state.sync_week)
                ]
                selected_target_text = f"{st.session_state.sync_year}年{st.session_state.sync_month}月 第{st.session_state.sync_week}週"
                period_days = 7
                df_sum_filtered["group_key"] = df_sum_filtered["日付"].apply(lambda d: f"{d.year}年{d.month}月 第{get_week_number(d)}週")
            elif st.session_state.sync_scope == "月単位":
                target_period_df = df_sum_filtered[
                    (df_sum_filtered["year_num"] == st.session_state.sync_year) &
                    (df_sum_filtered["month_num"] == st.session_state.sync_month)
                ]
                selected_target_text = f"{st.session_state.sync_year}年{st.session_state.sync_month}月"
                _, period_days = calendar.monthrange(st.session_state.sync_year, st.session_state.sync_month)
                df_sum_filtered["group_key"] = df_sum_filtered["日付"].dt.to_period("M").astype(str)
            else:
                target_period_df = df_sum_filtered[df_sum_filtered["year_num"] == st.session_state.sync_year]
                selected_target_text = f"{st.session_state.sync_year}年"
                period_days = 366 if calendar.isleap(st.session_state.sync_year) else 365
                df_sum_filtered["group_key"] = df_sum_filtered["日付"].dt.to_period("Y").astype(str)

            total_all = df["金額"].sum()
            selected_period_amount = target_period_df["金額"].sum()
            calculated_average = int(round(selected_period_amount / period_days)) if period_days > 0 else 0

            df_sorted = df_sum_filtered.sort_values(by="日付")
            period_sum_all = df_sorted.groupby("group_key", sort=False)["金額"].sum().reset_index()
            latest_period_text, latest_amount = (period_sum_all.iloc[-1]["group_key"], period_sum_all.iloc[-1]["金額"]) if not period_sum_all.empty else ("なし", 0)

            m_col1, m_col2, m_col3, m_col4 = st.columns(4)
            with m_col1: st.metric(label="📊 累計総支出額", value=f"{total_all:,} 円")
            with m_col2: st.metric(label=f"🧮 {selected_target_text} の支出額", value=f"{selected_period_amount:,} 円")
            with m_col3: st.metric(label=f"📐 {selected_target_text} の1日平均", value=f"{calculated_average:,} 円")
            with m_col4: st.metric(label=f"📅 直近データ ({latest_period_text})", value=f"{latest_amount:,} 円")

            st.write("---")

            cal_col, chart_col = st.columns(2)
            
            # --- [左側：支出カレンダー] ---
            with cal_col:
                st.subheader("📅 日付別の支出カレンダー")
                cal_ctrl1, cal_ctrl2, cal_ctrl3, cal_ctrl4 = st.columns([1, 2, 2, 1])
                with cal_ctrl1:
                    if st.button("◀", key="cal_prev"):
                        if st.session_state.sync_month == 1:
                            st.session_state.sync_month, st.session_state.sync_year = 12, st.session_state.sync_year - 1
                        else:
                            st.session_state.sync_month -= 1
                        st.rerun()
                with cal_ctrl2:
                    st.selectbox("年", options=years_options, index=years_options.index(st.session_state.sync_year), label_visibility="collapsed", key="cal_year_view", on_change=lambda: setattr(st.session_state, "sync_year", st.session_state.cal_year_view))
                with cal_ctrl3:
                    st.selectbox("月", options=months_options, index=st.session_state.sync_month - 1, label_visibility="collapsed", key="cal_month_view", on_change=lambda: setattr(st.session_state, "sync_month", months_options.index(st.session_state.cal_month_view) + 1))
                with cal_ctrl4:
                    if st.button("▶", key="cal_next"):
                        if st.session_state.sync_month == 12:
                            st.session_state.sync_month, st.session_state.sync_year = 1, st.session_state.sync_year + 1
                        else:
                            st.session_state.sync_month += 1
                        st.rerun()

                c = calendar.Calendar(firstweekday=6)
                month_days = c.monthdayscalendar(st.session_state.sync_year, st.session_state.sync_month)
                df_cal = df.copy()
                df_cal['day_num'], df_cal['month_num'], df_cal['year_num'] = df_cal['日付'].dt.day, df_cal['日付'].dt.month, df_cal['日付'].dt.year
                target_df = df_cal[(df_cal['year_num'] == st.session_state.sync_year) & (df_cal['month_num'] == st.session_state.sync_month)]
                
                html_code = f"""
                <style>
                    .cal-table {{ width: 100%; border-collapse: collapse; font-family: sans-serif; table-layout: fixed; }}
                    .cal-th {{ text-align: center; padding: 6px; background-color: #f0f2f6; font-size: 13px; color: #31333F; font-weight: bold; border: 1px solid #ddd; }}
                    .cal-td {{ vertical-align: top; height: 75px; padding: 4px; border: 1px solid #ddd; background-color: #ffffff; position: relative; }}
                    .cal-daynum {{ font-size: 12px; font-weight: bold; color: #555; }}
                    .cal-empty {{ background-color: #fafafa; border: 1px solid #ddd; }}
                    .expense-container {{ margin-top: 3px; font-size: 10px; line-height: 1.2; overflow: hidden; max-height: 52px; }}
                    .expense-item {{ white-space: nowrap; text-overflow: ellipsis; overflow: hidden; margin-bottom: 1px; font-weight: bold; color: #333; }}
                    .dot {{ display: inline-block; width: 6px; height: 6px; border-radius: 50%; margin-right: 3px; vertical-align: middle; border: 1px solid rgba(0,0,0,0.1); }}
                    .highlight-week {{ background-color: #CCFFCC !important; }}
                </style>
                <table class="cal-table">
                    <tr><th class="cal-th" style="color: #ef553b;">日</th><th class="cal-th">月</th><th class="cal-th">火</th><th class="cal-th">水</th><th class="cal-th">木</th><th class="cal-th">金</th><th class="cal-th" style="color: #636efa;">土</th></tr>
                """
                for w_idx, week in enumerate(month_days):
                    is_current_week_selected = (st.session_state.sync_scope == "週単位" and st.session_state.sync_week == (w_idx + 1))
                    row_class = ' class="highlight-week"' if is_current_week_selected else ''
                    html_code += "<tr>"
                    for day in week:
                        if day == 0:
                            html_code += '<td class="cal-td cal-empty"></td>'
                        else:
                            day_expenses = target_df[target_df['day_num'] == day]
                            expense_html = ""
                            if not day_expenses.empty:
                                expense_html += '<div class="expense-container">'
                                for _, row in day_expenses.groupby("カテゴリ")["金額"].sum().reset_index().iterrows():
                                    expense_html += f'<div class="expense-item"><span class="dot" style="background-color: {category_color_map.get(row["カテゴリ"], fallback_color)};"></span>{row["金額"]:,}円</div>'
                                expense_html += '</div>'
                            html_code += f'<td{row_class}><span class="cal-daynum">{day}</span>{expense_html}</td>'
                    html_code += "</tr>"
                html_code += "</table>"
                st.markdown(html_code, unsafe_allow_html=True)

            # --- [右側：カテゴリ割合] ---
            with chart_col:
                st.subheader("🍕 カテゴリ割合")
                def on_pie_scope_change():
                    if st.session_state.pie_scope_selection == "年単位": st.session_state.sync_scope = "年単位"
                    elif st.session_state.pie_scope_selection == "月単位": st.session_state.sync_scope = "月単位"

                pie_ctrl1, pie_ctrl2, pie_ctrl3 = st.columns([2, 1, 1])
                with pie_ctrl1:
                    st.radio("表示範囲:", options=["月単位", "年単位", "全期間"], horizontal=True, key="pie_scope_selection", on_change=on_pie_scope_change)
                with pie_ctrl2:
                    st.selectbox("年", options=years_options, index=years_options.index(st.session_state.sync_year), disabled=(st.session_state.pie_scope_selection == "全期間"), key="pie_select_year", on_change=lambda: setattr(st.session_state, "sync_year", st.session_state.pie_select_year))
                with pie_ctrl3:
                    st.selectbox("月", options=months_options, index=st.session_state.sync_month - 1, disabled=(st.session_state.pie_scope_selection in ["年単位", "全期間"]), key="pie_select_month", on_change=lambda: setattr(st.session_state, "sync_month", months_options.index(st.session_state.pie_select_month) + 1))

                df_pie = df.copy()
                df_pie['year_num'], df_pie['month_num'] = df_pie['日付'].dt.year, df_pie['日付'].dt.month
                
                if st.session_state.pie_scope_selection == "月単位":
                    filtered_pie_df = df_pie[(df_pie['year_num'] == st.session_state.sync_year) & (df_pie['month_num'] == st.session_state.sync_month)]
                    graph_title = f"{st.session_state.sync_year}年{st.session_state.sync_month}月の内訳"
                elif st.session_state.pie_scope_selection == "年単位":
                    filtered_pie_df = df_pie[df_pie['year_num'] == st.session_state.sync_year]
                    graph_title = f"{st.session_state.sync_year}年の内訳"
                else:
                    filtered_pie_df = df_pie
                    graph_title = "全期間の内訳"

                if filtered_pie_df.empty:
                    st.info(f"選択された期間 ({graph_title.replace('の内訳', '')}) のデータがありません。")
                else:
                    category_sum = filtered_pie_df.groupby("カテゴリ")["金額"].sum().reset_index()
                    category_sum["表示ラベル"] = category_sum.apply(lambda r: f"{r['カテゴリ']}: {r['金額']:,}円", axis=1)
                    label_color_map = {f"{c}: {a:,}円": category_color_map.get(c, fallback_color) for c, a in zip(category_sum["カテゴリ"], category_sum["金額"])}
                    
                    fig_pie = px.pie(category_sum, values="金額", names="表示ラベル", hole=0.3, title=graph_title, color="表示ラベル", color_discrete_map=label_color_map)
                    fig_pie.update_traces(textposition='inside', textinfo='percent', insidetextorientation='horizontal')
                    fig_pie.update_layout(height=420, margin=dict(l=20, r=20, t=40, b=10), legend=dict(yanchor="top", y=0.95, xanchor="left", x=1.0))
                    st.plotly_chart(fig_pie, use_column_width=True)

            with st.expander("📊 期間別集計の数値データ一覧を表示"):
                st.table(period_sum_all.rename(columns={"group_key": "期間", "金額": "合計金額 (円)"}))

if __name__ == "__main__":
    main()