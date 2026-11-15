# Shared chart theme and colours.

market_cols <- c(ASX = "#2a78d6", HKEX = "#eb6834", SGX = "#1baf7a")

theme_report <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "#e1e0d9", linewidth = 0.3),
      axis.title = ggplot2::element_text(colour = "#52514e"),
      axis.text = ggplot2::element_text(colour = "#52514e"),
      plot.title = ggplot2::element_text(face = "bold", colour = "#0b0b0b"),
      plot.title.position = "plot",
      plot.caption = ggplot2::element_text(colour = "#52514e", hjust = 0),
      plot.caption.position = "plot",
      legend.position = "top", legend.justification = "left",
      legend.title = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold", hjust = 0)
    )
}

# Formatting helpers for inline numbers
pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
num <- function(x, d = 2) formatC(x, format = "f", digits = d)
