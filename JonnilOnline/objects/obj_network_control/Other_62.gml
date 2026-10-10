/// @description Complete pending join and discovery DNS HTTP requests

#region /* DNS Response Dispatch */
/* Before join DNS state has been initialized, no HTTP response can be matched to
this controller. Ignore the event instead of reading a missing instance member */
if (!variable_instance_exists(id, "client_dns_request_id"))
{
	return;
}

/* request_id is the HTTP request identity supplied by the completion map.
is_join_dns marks the currently pending join request. is_discovery_dns begins
false until a discovery lookup with this identity is found */
var request_id = async_load[? "id"];
var is_join_dns = (request_id == client_dns_request_id);
var is_discovery_dns = false;

/* For a response outside the pending join lookup, inspect discovery requests.
A join response already has a known owner and needs no discovery scan */
if (!is_join_dns)
{
	/* Borrow the client service that owns outstanding server-list DNS requests */
	var net_client = scr_get_client();

	/* Only a present client request collection can establish discovery ownership.
	Without it, leave the discovery match false */
	if (is_struct(net_client) && variable_struct_exists(net_client, "discovery_dns_requests"))
	{
		/* Visit outstanding DNS entries by zero-based collection index until a matching
		request is found or the collection ends. Stop at the first match */
		for (var i = 0; i < array_length(net_client.discovery_dns_requests); i++)
		{
			/* A stored request identity matching this HTTP event belongs to discovery.
			Remember that owner and end the search instead of inspecting unrelated requests */
			if (net_client.discovery_dns_requests[i].request_id == request_id)
			{
				is_discovery_dns = true;
				break;
			}
		}
	}
}

/* Responses belonging to neither join nor discovery are unrelated HTTP work.
Return before reading a result or altering connection state */
if (!is_join_dns && !is_discovery_dns)
{
	return;
}

/* status is the HTTP completion state. Positive values indicate ongoing progress,
zero is successful completion and negative values represent failed requests */
var status = async_load[? "status"];

/* Positive HTTP status values are progress notifications, not completed DNS replies */
if (status > 0) return;

/* result is the completed HTTP response body candidate. Failed or absent bodies
leave the resolved address empty for the owning failure/fallback path */
var result = async_load[? "result"];

debug_log("DNS response received. status=" + string(status));

/* Begin with no resolved IPv4 address. Only a successful defined response body is
passed to the existing DNS JSON extractor */
var resolved_ip = "";

/* Successful completion with a defined body allows DNS result extraction.
Failed requests or absent data preserve the empty address instead of parsing it */
if (status == 0 && !is_undefined(result))
{
	resolved_ip = dns_extract_ip_from_json(result);
	debug_log("DNS resolved to: " + resolved_ip);
}

/* A join-owned response completes the pending join attempt using the extracted
address, or lets its join handler reject the empty failed lookup */
if (is_join_dns)
{
	client_join_with_resolved_ip(resolved_ip);
}

/* A discovery-owned response updates only its corresponding server-list request.
The join route does not take this path unless the stored request collections
also claim the same identity */
if (is_discovery_dns)
{
	/* Borrow the current client service again for discovery completion dispatch */
	var net_client = scr_get_client();

	/* Deliver the request identity and resolved address only when the client exposes
	its discovery completion handler. Missing support leaves list state unchanged */
	if (is_struct(net_client) && variable_struct_exists(net_client, "on_discovery_dns_resolved"))
	{
		net_client.on_discovery_dns_resolved(request_id, resolved_ip);
	}
}
#endregion /* DNS Response Dispatch END */
