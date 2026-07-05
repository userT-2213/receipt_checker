import calendar
import pandas as pd


def get_month_week_label(target_date):
    year = target_date.year
    month = target_date.month

    month_calendar = calendar.Calendar(firstweekday=6).monthdatescalendar(year, month)
    first_day = target_date.replace(day=1).date()
    last_day = (
        pd.Timestamp(year=year, month=month, day=1)
        + pd.offsets.MonthEnd(0)
    ).date()

    for week_index, week in enumerate(month_calendar, start=1):
        week_start = max(week[0], first_day)
        week_end = min(week[-1], last_day)

        if week_start <= target_date.date() <= week_end:
            return f"{year}年{month}月第{week_index}週", week_start, week_end

    return f"{year}年{month}月", target_date.date(), target_date.date()


def build_summary(expense_df, period_type):
    summary_df = expense_df.copy()

    summary_df["日付"] = pd.to_datetime(summary_df["日付"], errors="coerce")
    summary_df["支出額"] = pd.to_numeric(summary_df["支出額"], errors="coerce").fillna(0)
    summary_df = summary_df.dropna(subset=["日付"])

    if summary_df.empty:
        return summary_df

    if period_type == "週ごと":
        week_info = summary_df["日付"].apply(get_month_week_label)
        summary_df["集計期間"] = week_info.apply(lambda x: x[0])
        summary_df["期間開始日"] = week_info.apply(lambda x: x[1])
        summary_df["期間終了日"] = week_info.apply(lambda x: x[2])

    elif period_type == "月ごと":
        summary_df["集計期間"] = (
            summary_df["日付"].dt.year.astype(str)
            + "年"
            + summary_df["日付"].dt.month.astype(str)
            + "月"
        )
        summary_df["期間開始日"] = summary_df["日付"].dt.to_period("M").dt.start_time.dt.date
        summary_df["期間終了日"] = summary_df["日付"].dt.to_period("M").dt.end_time.dt.date

    else:
        summary_df["集計期間"] = summary_df["日付"].dt.year.astype(str) + "年"
        summary_df["期間開始日"] = summary_df["日付"].dt.to_period("Y").dt.start_time.dt.date
        summary_df["期間終了日"] = summary_df["日付"].dt.to_period("Y").dt.end_time.dt.date

    return summary_df