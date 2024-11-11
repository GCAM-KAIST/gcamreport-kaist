# left_df = rbind(prices_subsector_pre %>%
#         dplyr::filter(!grepl("biomass", sector)),
#       energy_price_fragmented_biomass) %>%
#   # add weights
#   dplyr::filter(year %in% gcam_years[gcam_years <= final_year.global])
#
# result = dplyr::left_join(left_df, en_weights,  by = c('scenario','region','year','sector','var'))
#
# unmatched <- result %>% dplyr::filter(dplyr::if_any(-one_of(names(left_df)), is.na))
# unmatched = unmatched %>% dplyr::filter(year == 2025, region == 'EU-15')
#
#
# aa = en_weights %>%
#   dplyr::filter(year == 2025, region == 'EU-15', grepl('Residential and Commercial',var), grepl('Gases',var))
#
# bb = left_df %>%
#   dplyr::filter(year == 2025, region == 'EU-15', grepl('Residential and Commercial',var), grepl('Gases',var))
#
#   # dplyr::mutate(sector = dplyr::if_else(grepl('Residential',var) & sector == 'delivered gas', 'gas', sector))
