import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def plot_grouped_bar_counts(dfs, column, labels=None, title=None, colors=None, figsize=(10, 6)):
    """
    Plots side-by-side grouped bar chart comparing value counts for a column across DataFrames.

    Args:
        dfs (list of pd.DataFrame or single pd.DataFrame): One or more DataFrames.
        column (str): Column name to compute value counts on.
        labels (list of str, optional): Labels for each DataFrame.
        title (str, optional): Plot title.
        colors (list of str, optional): Bar colors.
        figsize (tuple): Size of the figure.
    """
    if not isinstance(dfs, list):
        dfs = [dfs]

    if labels is None:
        labels = [f"Group {i+1}" for i in range(len(dfs))]

    if colors is None:
        colors = plt.cm.tab10.colors

    # Get full set of unique labels across all dfs
    all_keys = sorted(set().union(*[df[column].dropna().unique() for df in dfs]))
    x = np.arange(len(all_keys))  # base x locations

    # Width of each bar and shift offset
    total_width = 0.8
    num_groups = len(dfs)
    bar_width = total_width / num_groups
    offsets = np.linspace(-total_width/2 + bar_width/2, total_width/2 - bar_width/2, num_groups)

    # Start plotting
    fig, ax = plt.subplots(figsize=figsize)

    for i, (df, label) in enumerate(zip(dfs, labels)):
        counts = df[column].value_counts().to_dict()
        y_vals = [counts.get(key, 0) for key in all_keys]
        bars = ax.bar(x + offsets[i], y_vals, width=bar_width,
                      label=label, color=colors[i % len(colors)])

        # Annotate each bar
        for bar in bars:
            height = bar.get_height()
            if height > 0:
                ax.annotate(f'{height}',
                            xy=(bar.get_x() + bar.get_width() / 2, height),
                            xytext=(0, 3),
                            textcoords="offset points",
                            ha='center', va='bottom', fontsize=9)

    # Labels and styling
    ax.set_xticks(x)
    ax.set_xticklabels(all_keys, fontsize=11)
    ax.set_ylabel("Count", fontsize=12)
    ax.set_xlabel(column, fontsize=12)
    ax.set_title(title or f"Comparison by `{column}`", fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    plt.show()


def plot_grouped_bar_from_columns(df, columns, labels=None, title=None, colors=None, figsize=(10, 6)):
    """
    Plot side-by-side bar chart comparing value counts across multiple columns of the same DataFrame.

    Args:
        df (pd.DataFrame): The DataFrame containing all columns to compare.
        columns (list of str): List of column names to compare.
        labels (list of str, optional): Labels for legend. Defaults to column names.
        title (str, optional): Chart title.
        colors (list of str, optional): Bar colors.
        figsize (tuple): Size of the figure.
    """
    if labels is None:
        labels = columns
    if colors is None:
        colors = plt.cm.tab10.colors

    # Get all unique categories (x-axis labels)
    all_keys = sorted(set().union(*[df[col].dropna().unique() for col in columns]))
    x = np.arange(len(all_keys))
    
    # Bar width logic
    total_width = 0.8
    num_cols = len(columns)
    bar_width = total_width / num_cols
    offsets = np.linspace(-total_width/2 + bar_width/2, total_width/2 - bar_width/2, num_cols)

    # Plot
    fig, ax = plt.subplots(figsize=figsize)

    for i, (col, label) in enumerate(zip(columns, labels)):
        counts = df[col].value_counts().to_dict()
        y_vals = [counts.get(key, 0) for key in all_keys]
        bars = ax.bar(x + offsets[i], y_vals, width=bar_width,
                      label=label, color=colors[i % len(colors)])
        
        # Optional: annotate bars
        for bar in bars:
            height = bar.get_height()
            if height > 0:
                ax.annotate(f'{height}',
                            xy=(bar.get_x() + bar.get_width() / 2, height),
                            xytext=(0, 3),
                            textcoords="offset points",
                            ha='center', va='bottom', fontsize=9)

    ax.set_xticks(x)
    ax.set_xticklabels(all_keys, fontsize=11)
    ax.set_ylabel("Count", fontsize=12)
    ax.set_xlabel("Value", fontsize=12)
    ax.set_title(title or "Grouped Comparison of Columns", fontsize=14, fontweight='bold')
    ax.legend()
    ax.grid(axis="y", linestyle="--", alpha=0.6)
    plt.tight_layout()
    plt.show()
