from dataclasses import dataclass
from datetime import date


@dataclass
class Expense:
    date: str
    shop: str
    purpose: str
    items: str
    amount: int
    receipt_hash: str = ""

    def is_valid(self):
        if not self.date:
            return False, "日付を入力してください。"
        if not self.shop:
            return False, "店名を入力してください。"
        if not self.items:
            return False, "商品名を入力してください。"
        if self.amount <= 0:
            return False, "支出額は1円以上にしてください。"
        return True, ""

    @staticmethod
    def today_default():
        return str(date.today())