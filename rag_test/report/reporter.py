def generate_report(analysis_text):
    """
    Format the vulnerability analysis as a Markdown audit report.
    """
    report = "# Solidity Contract Vulnerability Audit Report\n\n"
    report += analysis_text
    return report
