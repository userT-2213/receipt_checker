import hashlib

import altair as alt
import pandas as pd
import streamlit as st
from PIL import Image

from expense_repository import ExpenseRepository
from expense_summary import build_summary
from models import Expense
from ocr_service import ReceiptOCRService


@st.cache_resource
def load_ocr_service():
    return ReceiptOCRService()


@st.cache_resource
def load_repository():
    return ExpenseRepository("expenses.db")


st.set_page_config(
    page_title="支出管理アプリ",
    layout="centered",
)

ocr_service = load_ocr_service()
repository = load_repository()

st.title("支出管理アプリ")
st.caption("レシート画像から支出を読み取り、保存・集計します。")

st.header("1. レシート画像のアップロード")

uploaded_file = st.file_uploader(
    "レシート画像をアップロードしてください",
    type=["png", "jpg", "jpeg"],
)

detected_date = Expense.today_default()
detected_shop = ""
detected_purpose = "その他"
detected_items = []
detected_price = 0
file_hash = ""

if uploaded_file is not None:
    try:
        file_bytes = uploaded_file.getvalue()
        file_hash = hashlib.md5(file_bytes).hexdigest()

        image = Image.open(uploaded_file)

        st.success("画像のアップロードに成功しました。")

        with st.spinner("レシートの文字を解析しています..."):
            result = ocr_service.analyze(image)

        detected_date = result["date"]
        detected_shop = result["shop"]
        detected_items = result["items"]
        detected_price = result["amount"]
        detected_purpose = result["purpose"]

        col1, col2 = st.columns(2)

        with col1:
            st.image(image, caption="元の画像", width=260)

        with col2:
            st.image(result["processed_image"], caption="OCR用画像", width=260)

        with st.expander("OCRで読み取った行を確認する"):
            lines = result["lines"]
            if lines:
                st.dataframe(
                    pd.DataFrame([{"読み取り行": line["text"]} for line in lines]),
                    use_container_width=True,
                )
            else:
                st.warning("文字を読み取れませんでした。")

    except Exception as e:
        st.error("画像の解析中にエラーが発生しました。")
        st.exception(e)

st.header("2. 支出情報の入力・確認")

items_newline_str = "\n".join(detected_items)

date_input = st.text_input("日付", value=detected_date)
shop_input = st.text_input("店名", value=detected_shop)

purpose_input = st.selectbox(
    "用途",
    ["食費", "日用品", "交通費", "衣服", "娯楽", "医療", "その他"],
    index=["食費", "日用品", "交通費", "衣服", "娯楽", "医療", "その他"].index(
        detected_purpose
        if detected_purpose in ["食費", "日用品", "交通費", "衣服", "娯楽", "医療", "その他"]
        else "その他"
    ),
)

item_input = st.text_area(
    "商品名",
    value=items_newline_str,
    height=120,
)

price_input = st.number_input(
    "支出額（円）",
    min_value=0,
    value=int(detected_price),
    step=1,
)

if st.button("この支出を保存する"):
    save_items = item_input.replace("\n", ", ")

    expense = Expense(
        date=date_input,
        shop=shop_input,
        purpose=purpose_input,
        items=save_items,
        amount=int(price_input),
        receipt_hash=file_hash,
    )

    success, message = repository.add_expense(expense)

    if success:
        st.success(message)
    else:
        st.error(message)

st.header("3. 現在の支出一覧")

expense_df = repository.load_expenses()

if expense_df.empty:
    st.info("登録された支出はありません。")
else:
    st.dataframe(
        expense_df[["日付", "店名", "用途", "商品名", "支出額"]],
        use_container_width=True,
    )

st.header("4. 支出集計")

if expense_df.empty:
    st.info("支出データを登録すると、週・月・年ごとの集計が表示されます。")
else:
    period_type = st.radio(
        "集計期間",
        ["週ごと", "月ごと", "年ごと"],
        horizontal=True,
    )

    summary_df = build_summary(expense_df, period_type)

    if summary_df.empty:
        st.warning("日付として読み取れるデータがないため、集計できません。")
    else:
        period_table = (
            summary_df[["集計期間", "期間開始日", "期間終了日"]]
            .drop_duplicates()
            .sort_values("期間開始日", ascending=False)
        )

        period_table["表示名"] = (
            period_table["集計期間"]
            + "（"
            + period_table["期間開始日"].astype(str)
            + "〜"
            + period_table["期間終了日"].astype(str)
            + "）"
        )

        selected_label = st.selectbox(
            "表示する期間",
            period_table["表示名"].tolist(),
        )

        selected_period = period_table.loc[
            period_table["表示名"] == selected_label,
            "集計期間",
        ].iloc[0]

        filtered_df = summary_df[summary_df["集計期間"] == selected_period]

        total_amount = int(filtered_df["支出額"].sum())

        st.subheader(f"{selected_label} の支出")
        st.metric("合計支出額", f"{total_amount:,} 円")

        purpose_summary = (
            filtered_df
            .groupby("用途", as_index=False)["支出額"]
            .sum()
            .sort_values("支出額", ascending=False)
        )

        st.subheader("用途別の支出割合")

        if purpose_summary.empty or purpose_summary["支出額"].sum() == 0:
            st.info("円グラフに表示できる支出データがありません。")
        else:
            pie_chart = (
                alt.Chart(purpose_summary)
                .mark_arc()
                .encode(
                    theta=alt.Theta(field="支出額", type="quantitative"),
                    color=alt.Color(field="用途", type="nominal"),
                    tooltip=[
                        alt.Tooltip("用途:N", title="用途"),
                        alt.Tooltip("支出額:Q", title="支出額", format=","),
                    ],
                )
                .properties(height=350)
            )

            st.altair_chart(pie_chart, use_container_width=True)

        st.subheader("期間内の支出一覧")

        display_df = filtered_df[
            ["日付", "店名", "用途", "商品名", "支出額"]
        ].copy()

        display_df["日付"] = display_df["日付"].dt.strftime("%Y-%m-%d")

        st.dataframe(display_df, use_container_width=True)

        st.subheader("期間別の合計支出")

        period_summary = (
            summary_df
            .groupby(["集計期間", "期間開始日", "期間終了日"], as_index=False)["支出額"]
            .sum()
            .sort_values("期間開始日", ascending=False)
        )

        period_summary["表示期間"] = (
            period_summary["集計期間"]
            + "（"
            + period_summary["期間開始日"].astype(str)
            + "〜"
            + period_summary["期間終了日"].astype(str)
            + "）"
        )

        st.dataframe(
            period_summary[["表示期間", "支出額"]],
            use_container_width=True,
        )