<%--<?xml version="1.0" encoding="ISO-8859-1" ?>--%>
<%--<%@ page language="java" contentType="text/html; charset=ISO-8859-1" pageEncoding="ISO-8859-1"%>--%>

<%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core" %>
<%@ taglib uri="http://java.sun.com/jsp/jstl/functions" prefix="fn" %>
<%@ taglib uri="http://java.sun.com/jsp/jstl/fmt" prefix="fmt" %>
<%@ taglib uri="http://displaytag.sf.net" prefix="dt" %>


<c:import url="template_header.jsp" >
    <c:param name="title">Main Page</c:param>
</c:import>

<div class="row">
    <div class="col-md-12">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title">Welcome to the JABAWS 2.2 website</h1>
            </div>
            <div class="panel-body">
                <div class="row">
                 <div class="col-md-6">
                        <p class="justify">
                            JABAWS is free software which provides web services conveniently
                            packaged to run on your local computer, server or cluster.
                        </p>
                        <p class="justify">
                            Services for multiple sequence alignment include
                            <a href="http://www.clustal.org/omega">Clustal Omega</a>,
                            <a href="http://www.clustal.org/clustal2">Clustal W</a>,
                            <a href="http://align.bmr.kyushu-u.ac.jp/mafft/software/">MAFFT</a>,
                            <a href="http://www.drive5.com/muscle">MUSCLE</a>,
                            <a href="http://www.tcoffee.org/Projects_home_page/t_coffee_home_page.html">T-Coffee</a>,
                            <a href="http://probcons.stanford.edu/">ProbCons</a>,
                            <a href="http://msaprobs.sourceforge.net/">MSAProbs</a>, and
                            <a href="http://sourceforge.net/projects/glprobs/">GLProbs</a>.
                            Analysis services allow prediction of protein disorder with
                            <a href="http://dis.embl.de/">DisEMBL</a>,
                            <a href="http://iupred.enzim.hu">IUPred</a>,
                            Jronn (a Java implementation of <a href="http://www.strubi.ox.ac.uk/RONN">Ronn</a> by P. Troshin and G. Barton, unpublished), and
                            <a href="http://globplot.embl.de/">GlobPlot</a>; and calculation of amino acid alignment conservation
                            with <a href="http://www.compbio.dundee.ac.uk/aacon">AACon</a>.
                            The secondary structure for an RNA aligment can be predicted with the RNAalifold program from the
                            <a href="http://www.tbi.univie.ac.at/RNA">Vienna RNA package</a>.
                        </p>
                        <p class="justify">
                            JABAWS web-services can be accessed through the <a href="http://www.jalview.org">Jalview</a> desktop
                            graphical user interface (GUI) (version 2.8 onwards) or the JABAWS Command Line Interface (CLI) client.
                            In this way you can perform computations on your sequences using the publicly available servers
                            running at the University of Dundee. Alternatively, JABAWS installation allows you to perform analysis
                            limited only by your own computing resources, by running it in your local computer, server or cluster.
                        </p>
                        <p class="justify">
                            The public server based on JABAWS 2.1 at the
                            <a href="https://www.dundee.ac.uk/">University of Dundee</a> has been in production since
                            October 2013 and serviced over 442,000 jobs for users worldwide.
                        </p>
                 </div>
                 <div class="col-md-6 ">
                    <img class="pull-right" src="${pageContext.request.contextPath}/static/img/aligment.png"
                         style="width:100%;height:100%" alt="Jalview: Sequence Alignment">
                 </div>
               </div>
            </div>
        </div>
    </div>
</div>
<div class="row">
    <div class="col-md-4">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title"><i class="fa fa-user" aria-hidden="true"></i>&nbsp;&nbsp;For Users</h1>
            </div>
            <div class="panel-body">
                <p class="justify">
                    <strong>Server: </strong><a href="${pageContext.request.contextPath}/#public_server">Public JABAWS server</a> or
                    the <a href="${pageContext.request.contextPath}/getting_started.jsp#va">JABAWS Virtual Appliance (VA)</a>
                </p>
                <p>
                    <strong>Client: </strong><a href="http://www.jalview.org/">Jalview</a>
                </p>
                <br/>
                <%--<p class="justify">--%>
                    <%--To use JABAWS web services on most operating systems, just download and <a href="2.1/manual_qs_va.html#qsc">install</a>--%>
                    <%--the JABAWS Virtual Appliance (VA). Or even easier - just start JABAWS machine on the cloud and point Jalview at it!--%>
                <%--</p>--%>
                <p><a class="btn btn-default" href="${pageContext.request.contextPath}/getting_started.jsp" role="button">Getting Started &raquo;</a></p>
            </div>
        </div>
    </div>
    <div class="col-md-4">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title"><i class="fa fa-flask" aria-hidden="true"></i>&nbsp;&nbsp;For Bioinformaticians/Developers</h1>
            </div>
            <div class="panel-body">
                <p>
                    <strong>Server: </strong><a href="${pageContext.request.contextPath}/#public_server">Public JABAWS server</a>,
                    the <a href="${pageContext.request.contextPath}/getting_started.jsp#va">JABAWS Virtual Appliance (VA)</a>, the
                <a href="${pageContext.request.contextPath}/getting_started.jsp#war">JABAWS Web Application aRchive (WAR)</a> or
                    <a href="${pageContext.request.contextPath}/docs/docker.html">Docker Containers</a>
                </p>
                <p>
                    <strong>Client: </strong><a href="http://www.jalview.org/">Jalview</a> or the
                    <a href="${pageContext.request.contextPath}/getting_started.jsp#client">Command Line Interface (CLI) Client</a>
                </p>
                <br/>
                <%--<p class="justify">--%>
                    <%--You can either use the JABAWS Virtual Appliance or the JABAWS Web Application aRchive (WAR) from your own computer or a lab server.--%>
                    <%--The WAR version gives greater flexibility but requires a bit more configuration. Alternatively you can script against our public--%>
                    <%--server (see below) with the command line client or you own script.--%>
                    <%--Check out the <a href="2.1/manual_qs_client.html#qsc">quick start guide</a> for further details.--%>
                <%--</p>--%>
                <p><a class="btn btn-default" href="${pageContext.request.contextPath}/getting_started.jsp" role="button">Getting Started &raquo;</a></p>
            </div>
        </div>
    </div>
    <div class="col-md-4">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title"><i class="fa fa-server" aria-hidden="true"></i>&nbsp;&nbsp;For System Administrators</h1>
            </div>
            <div class="panel-body">
                <p>
                    <strong>Server: </strong><a href="${pageContext.request.contextPath}/getting_started.jsp#war">
                    JABAWS Web Application aRchive (WAR)</a>
                </p>
                <p>
                    <strong>Client: </strong><a href="${pageContext.request.contextPath}/getting_started.jsp#client">
                    Command Line Interface (CLI) Client</a>
                </p>
                <br/>
                <%--<p class="justify">--%>
                    <%--JABAWS requires a Servlet 2.4 compatible servlet container like <a href="http://tomcat.apache.org">Apache Tomcat</a>--%>
                    <%--to run. Please check the <a href="2.1/manual_qs_war.html#qsc">quick start guide</a> for installation instructions.--%>
                <%--</p>--%>
                <p><a class="btn btn-default" href="${pageContext.request.contextPath}/getting_started.jsp" role="button">Getting Started &raquo;</a></p>
            </div>
        </div>
    </div>
</div>
<div class="row" id="public_server">
    <div class="col-md-12">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title">Public JABAWS Server</h1>
            </div>
            <div class="panel-body">

                <p class="justify">
                    You can access our public JABAWS web services with <a href="http://www.jalview.org/">Jalview</a>,
                    <a href="${pageContext.request.contextPath}/getting_started.jsp#client">JABAWS CLI</a>, or
                    <a href="${pageContext.request.contextPath}/docs/develop.html#accessing-jabaws-from-your-program">with your own program</a>.
                    The latest versions of Jalview (version 2.9 or later) are fully compatible
                    with JABAWS 2.2 and are configured to use the public JABAWS server by default.
                </p>
                <ul>
                    <li>The JABAWS public web services address is <strong><a href="http://www.compbio.dundee.ac.uk/jabaws">http://www.compbio.dundee.ac.uk/jabaws</a></strong> </li>
                    <li>A detailed description of the JABAWS web services is available from here:
                        <a href="${pageContext.request.contextPath}/RegistryWS?"
                           title="${pageContext.request.contextPath}/RegistryWS?" rel=nofollow">WSDL List</a></li>
                </ul>
                <p class="justify">
                    These web services accept submissions of <strong>less than one thousand sequences</strong>.
                    Should you find this to be insufficient for your needs, or if you are concerned about privacy,
                    then you can download and
                    run the <a href="${pageContext.request.contextPath}/getting_started.jsp#war">JABAWS WAR</a> on your own hardware.
                </p>
            </div>
        </div>
    </div>
</div>
<div class="row">
    <div class="col-md-12">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title">New in JABAWS 2.2</h1>
            </div>
            <div class="panel-body">
                <p class="justify">
                    The current JABAWS version is 2.2 released on 18 August 2017. Among the new developments in JABAWS 2.2 are:
                                </p>
                    <ul>
                        <li>Several programs included in JABAWS, including Clustal Omega, ClustalW, Mafft and T-coffee, were updated.
                        <li><a href="http://www.compbio.dundee.ac.uk/aacon/">AACon</a>
                            was also updated to the latest release, version 1.1.</li>
                        <li><a href="${pageContext.request.contextPath}/ServiceStatus" >Service Status</a> and
                            <a href="${pageContext.request.contextPath}/PublicAnnualStat" >Usage Statistics</a>
                            are now cached and refreshed asynchronously for improved Website loading times.</li>
                        <li>We now provide a <a href="https://www.docker.com/" >Docker</a> image which allows for JABAWS to be run in Docker containers. </li>
                        <li>The website looks were updated to use the Twitter <a href="http://getbootstrap.com/">Bootstrap</a> CSS framework,
                            and documentation pages are now generated with <a href="http://www.sphinx-doc.org/en/stable/">Sphinx</a>.
                        </li>
                    </ul>
                <p class="justify">
                    More information about the changes introduced in the latest release can be found in the
                    <a href="${pageContext.request.contextPath}/docs/changelog.html">changelog</a> pages.
                </p>
            </div>
        </div>
    </div>
</div>

<div class="row">
    <div class="col-md-12">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title">Reference</h1>
            </div>
            <div class="panel-body">
		<p class="justify">
                    Peter V Troshin,  James B Procter,  Alexander Sherstnev,  Daniel L Barton,  F&aacute;bio Madeira and Geoffrey J. Barton (2018)
                    <strong>JABAWS 2.2 Distributed Web Services for Bioinformatics: Protein Disorder, Conservation and RNA Secondary Structure</strong>
                    <em>Bioinformatics</em> bty045. doi: <a href="https://doi.org/10.1093/bioinformatics/bty045">
                    10.1093/bioinformatics/bty045</a>.
                </p>
                <p class="justify">
                    Peter V. Troshin, James B. Procter and Geoffrey J. Barton (2011)
                    <strong>Java Bioinformatics Analysis Web Services for Multiple Sequence Alignment - JABAWS:MS</strong>
                    <em>Bioinformatics</em> 27 (14): 2001-2002. doi: <a href="https://doi.org/10.1093/bioinformatics/btr304">
                    10.1093/bioinformatics/btr304</a>.
                </p>
            </div>
        </div>
    </div>
</div>
<%--</div>--%>
<div class="row">
    <div class="col-md-12">
        <div class="panel panel-default">
            <div class="panel panel-heading">
                <h1 class="panel-title">ELIXIR-UK</h1>
            </div>
            <div class="panel-body">

                <div class="row">
                    <div class="col-md-3">
                        <span class="align-middle"><a href="https://www.elixir-europe.org/">
                            <img src="static/img/elixir_uk.png" style="width:80%;height:80%" alt="ELIXIR UK"
                                 title="UK BBSRC"/></a>
                        </span>
                    </div>
                    <div class="col-md-9">
                        <p class="justify">
                            <a href="http://www.compbio.dundee.ac.uk/jabaws/">JABAWS</a> and
                            <a href="http://www.compbio.dundee.ac.uk/aacon/">AACon</a> are part of the
                            "Dundee Resource for Protein Sequence analysis and structure prediction", which is an
                            <a href="http://www.elixir-uk.org/">ELIXIR-UK</a> resource.
                        </p>
                        <div class="row">
                            <div class="col-md-4">
                                <span class="align-left"><a href="http://www.bbsrc.ac.uk/">
                                    <img src="static/img/bbsrc_flat.jpg" style="width:110%;height:110%" alt="UK BBSRC"
                                         title="UK BBSRC"/></a>
                                </span>
                            </div>
                            <div class="col-md-4">
                                <span class="align-right"><a href="http://www.jalview.org/">
                                    <img src="static/img/jalview.svg" style="width:100%;height:100%" alt="JALVIEW"
                                         title="JALVIEW"/></a>
                                </span>
                            </div>
                            <div class="col-md-4">
                                <span class="align-right"><a href="http://www.compbio.dundee.ac.uk/jpred/index.html">
                                    <img src="static/img/jpred4.svg" style="width:100%;height:100%" alt="JPRED"
                                         title="JPRED"/></a>
                                </span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<jsp:include page="template_footer.jsp" />
