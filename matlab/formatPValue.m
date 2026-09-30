function s = formatPValue(p)
%FORMATPVALUE  Compact p-value string for reports and plot annotations.
    if isempty(p) || numel(p) ~= 1 || isnan(p)
        s = 'N/A';
    elseif p < 1e-4
        s = sprintf('%.3e', p);
    else
        s = sprintf('%.4f', p);
    end
end
