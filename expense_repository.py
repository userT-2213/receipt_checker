import sqlite3
import pandas as pd
from models import Expense


class ExpenseRepository:
    def __init__(self, db_path="expenses.db"):
        self.db_path = db_path
        self.initialize()

    def connect(self):
        return sqlite3.connect(self.db_path)

    def initialize(self):
        with self.connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS expenses (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    date TEXT NOT NULL,
                    shop TEXT NOT NULL,
                    purpose TEXT NOT NULL,
                    items TEXT NOT NULL,
                    amount INTEGER NOT NULL,
                    receipt_hash TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            conn.commit()

    def is_duplicate_receipt(self, receipt_hash):
        if not receipt_hash:
            return False

        with self.connect() as conn:
            cursor = conn.execute(
                "SELECT COUNT(*) FROM expenses WHERE receipt_hash = ?",
                (receipt_hash,),
            )
            return cursor.fetchone()[0] > 0

    def add_expense(self, expense: Expense):
        is_valid, message = expense.is_valid()
        if not is_valid:
            return False, message

        if expense.receipt_hash and self.is_duplicate_receipt(expense.receipt_hash):
            return False, "このレシートはすでに登録されています。"

        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO expenses
                (date, shop, purpose, items, amount, receipt_hash)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    expense.date,
                    expense.shop,
                    expense.purpose,
                    expense.items,
                    expense.amount,
                    expense.receipt_hash,
                ),
            )
            conn.commit()

        return True, "データを保存しました。"

    def load_expenses(self):
        with self.connect() as conn:
            return pd.read_sql_query(
                """
                SELECT
                    date AS 日付,
                    shop AS 店名,
                    purpose AS 用途,
                    items AS 商品名,
                    amount AS 支出額,
                    receipt_hash AS レシートID
                FROM expenses
                ORDER BY date DESC, id DESC
                """,
                conn,
            )