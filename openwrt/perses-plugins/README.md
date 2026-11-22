# perses-plugins

The [Perses plugins](https://github.com/perses/plugins) beyond the four the
[perses](../perses) package comes with (`DatasourceVariable`,
`StaticListVariable`, `TimeSeriesChart`, `Markdown`), one package each, so a
device carries only the ones its dashboards use:

```sh
apk add perses-plugin-prometheus perses-plugin-statchart
```

| Package | What |
|---------|------|
| `perses-plugin-prometheus` | Prometheus and VictoriaMetrics datasource and queries |
| `perses-plugin-victorialogs` | VictoriaLogs datasource and log queries |
| `perses-plugin-statchart` | single-value stat panels |
| `perses-plugin-gaugechart` | gauge panels |
| `perses-plugin-barchart` | bar charts |
| `perses-plugin-piechart` | pie charts |
| `perses-plugin-table` | table panels |
| `perses-plugin-timeseriestable` | time series as a table |
| `perses-plugin-logstable` | log lines as a table |
| `perses-plugin-statushistorychart` | status history panels |
| `perses-plugin-heatmapchart` | heat maps |
| `perses-plugin-histogramchart` | histograms |
| `perses-plugin-logexplorer` | the Explore view for logs (perses option `explorer`) |

Each is `noarch`, carries upstream's own version, and is ~3.6MB, ~11MB once
Perses unpacks it into its `data_dir` on its next start. Installing or
removing one restarts perses, which loads plugins only when it starts.
